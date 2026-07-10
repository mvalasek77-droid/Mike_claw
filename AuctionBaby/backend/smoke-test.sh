#!/usr/bin/env bash
#
# Staging smoke test for the Auction Baby payout Worker.
#
# Exercises the full money path against STRIPE TEST MODE (fake money):
#   health → funding (before) → optional connect → transfer → funding (after)
#   → ledger. Shows exactly what each endpoint returns so you can confirm the
#   payout notification + top-up math without touching real money.
#
# It never sends or stores secrets anywhere — you pass them as env vars and
# they live only in your shell for this run.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   export STAGING_URL="https://auctionbaby-payout-staging.<you>.workers.dev"
#   export APP_SHARED_SECRET="<the staging APP_SHARED_SECRET you set>"
#   # An existing TEST-MODE connected account that has finished onboarding
#   # (payouts enabled). Create one via step 3 below, finish onboarding with
#   # Stripe's test data, then re-run with TEST_ACCOUNT_ID set.
#   export TEST_ACCOUNT_ID="acct_xxx"
#   export AMOUNT_USD="1.00"           # optional, defaults to 1.00
#
#   bash smoke-test.sh
#
# Tip: a transfer larger than your test-mode platform balance is SUPPOSED to
# fail with insufficient funds — that path fires the 🚨 NSF email, which is
# itself a valid thing to test. Set AMOUNT_USD high to exercise it.
# ────────────────────────────────────────────────────────────────────────────

set -uo pipefail

URL="${STAGING_URL:-}"
SECRET="${APP_SHARED_SECRET:-}"
ACCOUNT="${TEST_ACCOUNT_ID:-}"
AMOUNT="${AMOUNT_USD:-1.00}"

if [[ -z "$URL" || -z "$SECRET" ]]; then
  echo "ERROR: set STAGING_URL and APP_SHARED_SECRET first (see header of this file)." >&2
  exit 1
fi

# Pretty-print JSON if jq is available; otherwise raw.
pp() { if command -v jq >/dev/null 2>&1; then jq .; else cat; fi; }
auth=(-H "Authorization: Bearer ${SECRET}")
hr() { printf '\n────────────────────────────────────────────────────────\n%s\n────────────────────────────────────────────────────────\n' "$1"; }

hr "1. Health check (no auth)  GET /"
curl -s "${URL}/" | pp

hr "2. Float funding BEFORE  GET /payouts/funding"
echo "(availableUSD, bufferUSD, topUpNeededUSD, salesToday*)"
curl -s "${auth[@]}" "${URL}/payouts/funding" | pp

if [[ -z "$ACCOUNT" ]]; then
  hr "3. No TEST_ACCOUNT_ID set — creating a Connect account"
  echo "Open the onboardingUrl below in a browser (TEST MODE banner), use Stripe's"
  echo "test data / 'Skip' to finish, then re-run with TEST_ACCOUNT_ID set to the"
  echo "accountId printed here."
  curl -s "${auth[@]}" -H "Content-Type: application/json" \
    -d '{"accountName":"Smoke Tester","accountEmail":"smoke+test@example.com","country":"CA"}' \
    "${URL}/payouts/connect" | pp
  echo
  echo "Stopping here — set TEST_ACCOUNT_ID and run again to test the transfer."
  exit 0
fi

hr "3. Account status  GET /payouts/status?account_id=${ACCOUNT}"
echo "(payoutsEnabled must be true for a transfer to land)"
curl -s "${auth[@]}" "${URL}/payouts/status?account_id=${ACCOUNT}" | pp

hr "4. Transfer ${AMOUNT} (a paid date)  POST /payouts/transfer"
echo "On success: ledger records it + you get the 💰 payout email."
echo "On insufficient funds: 502 + the 🚨 NSF email fires."
DATE_ID="smoke-$(date +%s)"
curl -s "${auth[@]}" -H "Content-Type: application/json" \
  -d "{\"account_id\":\"${ACCOUNT}\",\"amount_usd\":${AMOUNT},\"date_id\":\"${DATE_ID}\",\"idempotency_key\":\"date_${DATE_ID}\",\"memo\":\"smoke test date\"}" \
  "${URL}/payouts/transfer" | pp

echo
echo "(waiting 2s for ledger + counter writes to settle…)"
sleep 2

hr "5. Float funding AFTER  GET /payouts/funding"
echo "salesTodayCount/USD should have incremented if the transfer succeeded."
curl -s "${auth[@]}" "${URL}/payouts/funding" | pp

hr "6. Ledger for this account  GET /ledger?account_id=${ACCOUNT}"
echo "Newest first — you should see the transfer (or an nsf entry if it failed)."
curl -s "${auth[@]}" "${URL}/ledger?account_id=${ACCOUNT}&limit=5" | pp

hr "7. Ledger totals  GET /ledger/summary"
curl -s "${auth[@]}" "${URL}/ledger/summary" | pp

hr "8. Refund queue (empty unless Apple sent a refund)  GET /refunds/pending"
curl -s "${auth[@]}" "${URL}/refunds/pending?app_account_token=00000000-0000-0000-0000-000000000000" | pp

hr "Done"
echo "Check ${OPERATOR_EMAIL:-mvalasek77@gmail.com} for the payout (or NSF) email."
echo "Everything above ran in Stripe TEST MODE — no real money moved."
