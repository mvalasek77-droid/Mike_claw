#!/usr/bin/env bash
# End-to-end test for the "Reserve the date" booking fee, using genuinely
# HMAC-signed Stripe webhook events. Verifies that a reservation:
#   - marks exactly one date booked (keyed by matchId)
#   - NEVER credits Gavels (it's a real-world fee, not a digital good)
#   - is idempotent per event id
#   - un-reserves on refund
#
# All ids are timestamped per run, so it's safe to re-run against a persistent
# local KV (unlike a fixed-id smoke test).
#
# Usage:
#   BASE_URL=http://127.0.0.1:8788 \
#   APP_SHARED_SECRET=devsecret \
#   STRIPE_WEBHOOK_SECRET=whsec_localtest ./reserve-e2e-test.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8788}"
SECRET="${APP_SHARED_SECRET:-devsecret}"
WHSEC="${STRIPE_WEBHOOK_SECRET:-whsec_localtest}"
STAMP="$(date +%s)"
USER="resu-${STAMP}"
MATCH="match-${STAMP}"
PI="pi_res_${STAMP}"
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

status()  { curl -s "${AUTH[@]}" "${BASE_URL}/reserve/status?matchId=${MATCH}" ; }
balance() { curl -s "${AUTH[@]}" "${BASE_URL}/balance?userId=${USER}" ; }

echo "→ 0. reserve/info exposes enabled + the tier ladder"
INFO="$(curl -s "${BASE_URL}/reserve/info")"
check "enabled=true" "$INFO" '"enabled":true'
check "has \$10.00 tier" "$INFO" '"display":"$10.00"'
check "has \$100.00 tier" "$INFO" '"display":"$100.00"'

echo "→ 0b. checkout rejects an amount not on the allow-list (before Stripe)"
BADAMT=$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"matchId\":\"${MATCH}\",\"userId\":\"${USER}\",\"amountCents\":777}" \
  "${BASE_URL}/reserve/checkout")
check "400 for off-ladder amount" "$BADAMT" '400'

echo "→ 1. date starts un-reserved"
check "reserved=false" "$(status)" '"reserved":false'

echo "→ 2. signed reservation webhook books the date"
EVT="evt_res_${STAMP}_1"
BODY=$(cat <<JSON
{"id":"${EVT}","type":"checkout.session.completed","data":{"object":{
"id":"cs_res_${STAMP}","payment_status":"paid","payment_intent":"${PI}",
"client_reference_id":"${USER}",
"metadata":{"kind":"reservation","matchId":"${MATCH}","userId":"${USER}","amountCents":"2500"}}}}
JSON
)
BODY=$(echo "$BODY" | tr -d '\n')
check "webhook reserved" "$(sign_and_post "$BODY")" '"reserved":true'
check "status reserved=true" "$(status)" '"reserved":true'
check "status carries amount (2500)" "$(status)" '"amountCents":2500'

echo "→ 3. a reservation must NOT credit Gavels"
check "gavel balance still 0" "$(balance)" '"gavels":0'

echo "→ 4. same event id replayed → duplicate, no side effects"
check "duplicate flagged" "$(sign_and_post "$BODY")" '"duplicate":true'
check "still reserved" "$(status)" '"reserved":true'

echo "→ 5. unsigned reservation webhook rejected"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
  -d "$BODY" "${BASE_URL}/webhook")
check "400 without signature" "$CODE" '400'

echo "→ 6. refund un-reserves the date"
EVT_REF="evt_res_${STAMP}_ref"
BODY_REF="{\"id\":\"${EVT_REF}\",\"type\":\"charge.refunded\",\"data\":{\"object\":{\"id\":\"ch_res_${STAMP}\",\"payment_intent\":\"${PI}\",\"amount\":500,\"amount_refunded\":500}}}"
check "refund accepted" "$(sign_and_post "$BODY_REF")" '"reservationRefunded":true'
check "status reserved=false" "$(status)" '"reserved":false'
check "gavel balance untouched" "$(balance)" '"gavels":0'

echo
if [ "$FAIL" -gt 0 ]; then echo "❌ ${FAIL} failed, ${PASS} passed"; exit 1; fi
echo "✅ all ${PASS} reservation checks passed"
