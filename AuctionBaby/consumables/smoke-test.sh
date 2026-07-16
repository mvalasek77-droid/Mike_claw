#!/usr/bin/env bash
# Smoke test for the Auction Baby consumables Worker. Runs the public + authed
# happy paths against a running instance (local `wrangler dev` or a deployed
# URL).
#
# Usage:
#   BASE_URL=http://127.0.0.1:8787 APP_SHARED_SECRET=devsecret ./smoke-test.sh
#
# The webhook path is NOT covered here — it requires a real Stripe signature.
# Use the Stripe CLI for that:  stripe listen --forward-to $BASE_URL/webhook
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8787}"
SECRET="${APP_SHARED_SECRET:-devsecret}"
USER_ID="${USER_ID:-smoke-user}"
AUTH=(-H "Authorization: Bearer ${SECRET}")

echo "→ GET /health"
curl -fsS "${BASE_URL}/health" | tee /dev/stderr | grep -q '"ok":true'

echo; echo "→ GET /catalog"
curl -fsS "${BASE_URL}/catalog" | tee /dev/stderr | grep -q '"packs"'

echo; echo "→ GET /balance (unauth should 401)"
code=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/balance?userId=${USER_ID}")
[ "$code" = "401" ] && echo "  ok: 401 without auth" || { echo "  FAIL: got $code"; exit 1; }

echo; echo "→ GET /balance (authed)"
curl -fsS "${AUTH[@]}" "${BASE_URL}/balance?userId=${USER_ID}" | tee /dev/stderr | grep -q '"gavels"'

echo; echo "→ POST /consume with no balance should 402"
code=$(curl -s -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"userId\":\"${USER_ID}\",\"gavels\":10,\"idempotencyKey\":\"smoke-1\"}" \
  "${BASE_URL}/consume")
[ "$code" = "402" ] && echo "  ok: 402 insufficient gavels" || { echo "  FAIL: got $code"; exit 1; }

echo; echo "→ POST /checkout (needs a valid STRIPE_SECRET_KEY to succeed)"
curl -s "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"packId\":\"gavels_handful\",\"userId\":\"${USER_ID}\"}" \
  "${BASE_URL}/checkout" | tee /dev/stderr | grep -Eq '"url"|Checkout failed' \
  && echo "  ok: checkout reached Stripe (url or a Stripe error means wiring is correct)"

echo; echo "✅ smoke test passed"
