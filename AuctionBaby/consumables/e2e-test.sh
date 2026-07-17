#!/usr/bin/env bash
# End-to-end money-path test for the consumables Worker, using genuinely
# HMAC-signed Stripe webhook events — verifies the FULL credit/refund/consume
# lifecycle against a running instance (local `wrangler dev` or staging).
#
# Usage:
#   BASE_URL=http://127.0.0.1:8787 \
#   APP_SHARED_SECRET=devsecret \
#   STRIPE_WEBHOOK_SECRET=whsec_localtest ./e2e-test.sh
#
# Covers:
#   1. signed checkout.session.completed → credits
#   2. same event id replayed          → duplicate, no double-credit
#   3. unsigned webhook                → 400 rejected
#   4. unpaid completed event          → skipped, no credit
#   5. async_payment_succeeded         → credits (delayed payment methods)
#   6. /consume with idempotency key   → drains once; replay returns prior
#   7. partial charge.refunded         → proportional debit
#   8. second partial (cumulative)     → only the delta debited
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
SECRET="${APP_SHARED_SECRET:-devsecret}"
WHSEC="${STRIPE_WEBHOOK_SECRET:-whsec_localtest}"
USER="e2e-$(date +%s)"
AUTH=(-H "Authorization: Bearer ${SECRET}")
PASS=0; FAIL=0

sign_and_post() {  # $1 = raw JSON body → posts to /webhook with a valid signature
  local body="$1"
  local t; t=$(date +%s)
  local sig; sig=$(printf '%s.%s' "$t" "$body" \
    | openssl dgst -sha256 -hmac "$WHSEC" -hex | sed 's/^.* //')
  curl -s -H "Stripe-Signature: t=${t},v1=${sig}" \
       -H 'Content-Type: application/json' -d "$body" "${BASE_URL}/webhook"
}

check() {  # $1 = label, $2 = actual, $3 = expected-substring
  if echo "$2" | grep -q "$3"; then
    echo "  ✓ $1"; PASS=$((PASS+1))
  else
    echo "  ✗ $1 — expected '$3' in: $2"; FAIL=$((FAIL+1))
  fi
}

balance() { curl -s "${AUTH[@]}" "${BASE_URL}/balance?userId=${USER}" ; }

echo "→ 1. signed checkout.session.completed credits 5,000 Gavels"
EVT1="evt_e2e_$(date +%s)_1"
BODY1=$(cat <<JSON
{"id":"${EVT1}","type":"checkout.session.completed","data":{"object":{
"id":"cs_e2e_1","payment_status":"paid","payment_intent":"pi_e2e_1",
"client_reference_id":"${USER}",
"metadata":{"userId":"${USER}","packId":"gavels_stack","gavels":"5000"}}}}
JSON
)
BODY1=$(echo "$BODY1" | tr -d '\n')
check "webhook accepted" "$(sign_and_post "$BODY1")" '"received":true'
check "balance = 5000"  "$(balance)" '"gavels":5000'

echo "→ 2. same event id replayed → duplicate, no double-credit"
check "duplicate flagged" "$(sign_and_post "$BODY1")" '"duplicate":true'
check "balance still 5000" "$(balance)" '"gavels":5000'

echo "→ 3. unsigned webhook rejected"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "$BODY1" "${BASE_URL}/webhook")
check "400 without signature" "$CODE" '400'

echo "→ 4. unpaid completed event → skipped"
BODY_UNPAID='{"id":"evt_e2e_unpaid","type":"checkout.session.completed","data":{"object":{"id":"cs_e2e_2","payment_status":"unpaid","payment_intent":"pi_e2e_2","client_reference_id":"'"$USER"'","metadata":{"userId":"'"$USER"'","packId":"gavels_handful","gavels":"1000"}}}}'
check "skipped: unpaid" "$(sign_and_post "$BODY_UNPAID")" '"skipped":"unpaid"'
check "balance unchanged" "$(balance)" '"gavels":5000'

echo "→ 5. async_payment_succeeded credits the delayed payment"
BODY_ASYNC='{"id":"evt_e2e_async","type":"checkout.session.async_payment_succeeded","data":{"object":{"id":"cs_e2e_2","payment_status":"paid","payment_intent":"pi_e2e_2","client_reference_id":"'"$USER"'","metadata":{"userId":"'"$USER"'","packId":"gavels_handful","gavels":"1000"}}}}'
check "credited" "$(sign_and_post "$BODY_ASYNC")" '"received":true'
check "balance = 6000" "$(balance)" '"gavels":6000'

echo "→ 6. /consume drains 1,500 once; replay returns prior result"
DRAIN=$(curl -s "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d '{"userId":"'"$USER"'","gavels":1500,"idempotencyKey":"e2e-drain-1","reason":"e2e"}' \
  "${BASE_URL}/consume")
check "spent 1500" "$DRAIN" '"spent":1500'
check "balance = 4500" "$(balance)" '"gavels":4500'
REPLAY=$(curl -s "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d '{"userId":"'"$USER"'","gavels":1500,"idempotencyKey":"e2e-drain-1","reason":"e2e"}' \
  "${BASE_URL}/consume")
check "replay flagged" "$REPLAY" '"replay":true'
check "balance still 4500" "$(balance)" '"gavels":4500'

echo "→ 7. partial charge.refunded → proportional debit"
# pi_e2e_1 bought 5,000 Gavels for \$19.99 (1999¢). Refund 999¢ →
# debit round(5000 * 999/1999) = 2499 → balance 4500-2499 = 2001.
BODY_REF1='{"id":"evt_e2e_ref1","type":"charge.refunded","data":{"object":{"id":"ch_e2e_1","payment_intent":"pi_e2e_1","amount":1999,"amount_refunded":999}}}'
check "refund accepted" "$(sign_and_post "$BODY_REF1")" '"received":true'
check "balance = 2001" "$(balance)" '"gavels":2001'

echo "→ 8. second partial (cumulative 1999¢) → only the delta debited"
# newly refunded = 1999-999 = 1000¢ → debit round(5000*1000/1999) = 2501
# → balance 2001-2501 floors at 0... = max(0, 2001-2501) = 0.
BODY_REF2='{"id":"evt_e2e_ref2","type":"charge.refunded","data":{"object":{"id":"ch_e2e_1","payment_intent":"pi_e2e_1","amount":1999,"amount_refunded":1999}}}'
check "refund accepted" "$(sign_and_post "$BODY_REF2")" '"received":true'
check "balance floored at 0" "$(balance)" '"gavels":0'

echo
echo "ledger tail:"
curl -s "${AUTH[@]}" "${BASE_URL}/ledger?userId=${USER}" | head -c 600; echo
echo
if [ "$FAIL" -gt 0 ]; then echo "❌ ${FAIL} failed, ${PASS} passed"; exit 1; fi
echo "✅ all ${PASS} checks passed"
