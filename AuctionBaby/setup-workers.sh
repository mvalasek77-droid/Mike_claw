#!/usr/bin/env bash
# One-shot provisioning for Auction Baby's two Cloudflare Workers:
#
#   backend/      auctionbaby-payout       — money OUT (Stripe Connect payouts,
#                                            Apple refund routing, admin console)
#   consumables/  auctionbaby-consumables  — money IN  (Stripe Checkout web
#                                            Gavel shop)
#
# Run from the AuctionBaby directory on a machine that's logged in to
# Cloudflare (`npx wrangler login`, or export CLOUDFLARE_API_TOKEN) with your
# Stripe secret key at hand:
#
#   STRIPE_SECRET_KEY=sk_test_… ./setup-workers.sh            # staging/test
#   STRIPE_SECRET_KEY=sk_live_… ENV=production ./setup-workers.sh
#
# What it does, in order, per worker:
#   1. Creates the KV namespace (reuses it if it already exists) and patches
#      the real id into wrangler.toml in place of the placeholder.
#   2. Generates ONE shared APP_SHARED_SECRET (or reuses $APP_SHARED_SECRET)
#      and installs it on both workers — the app carries a single secret.
#   3. Installs STRIPE_SECRET_KEY on both workers.
#   4. Deploys both workers and captures their workers.dev URLs.
#   5. Registers the consumables Stripe webhook via the Stripe API
#      (checkout.session.completed, checkout.session.async_payment_succeeded,
#      charge.refunded), captures the returned whsec_… signing secret, and
#      installs it as STRIPE_WEBHOOK_SECRET. Nothing manual.
#   6. Prints the exact lines to paste into Config/Secrets.xcconfig, plus the
#      remaining by-hand steps (App Store Server Notifications URL; the payout
#      worker's own Stripe webhook, whose Connect event set you may want to
#      curate in the dashboard).
#   7. Runs each worker's smoke test against the deployed URL.
set -euo pipefail

ENV="${ENV:-staging}"                      # staging (default) or production
STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:?export STRIPE_SECRET_KEY=sk_test_… first}"
cd "$(dirname "$0")"

if [ "$ENV" = "production" ]; then
  ENV_FLAG=(); ENV_SUFFIX=""
else
  ENV_FLAG=(--env staging); ENV_SUFFIX="-staging"
fi

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── helpers ──────────────────────────────────────────────────────────────────

# ensure_kv <dir> <worker-name>  → creates/reuses the KV namespace and patches
# the placeholder id in wrangler.toml for the chosen env.
ensure_kv() {
  local dir="$1" name="$2" title id
  # Wrangler names namespaces "<worker>-<binding>" (+ "_preview" variants);
  # match on the worker+env prefix.
  title="${name}${ENV_SUFFIX}-KV"
  pushd "$dir" >/dev/null
  id=$(npx wrangler kv namespace list 2>/dev/null \
        | grep -B2 -A2 "\"title\": \"${title}\"" | grep '"id"' \
        | head -1 | sed 's/.*"id": *"\([^"]*\)".*/\1/' || true)
  if [ -z "$id" ]; then
    say "Creating KV namespace for ${name}${ENV_SUFFIX}…"
    id=$(npx wrangler kv namespace create KV "${ENV_FLAG[@]}" 2>/dev/null \
          | grep -o 'id = "[^"]*"' | head -1 | sed 's/id = "\(.*\)"/\1/')
  else
    say "Reusing existing KV namespace for ${name}${ENV_SUFFIX} (${id})"
  fi
  [ -n "$id" ] || { echo "Could not create/find KV namespace for ${name}"; exit 1; }
  if [ "$ENV" = "production" ]; then
    sed -i.bak "s/REPLACE_WITH_KV_NAMESPACE_ID/${id}/" wrangler.toml
  else
    sed -i.bak "s/REPLACE_WITH_STAGING_KV_NAMESPACE_ID/${id}/" wrangler.toml
  fi
  rm -f wrangler.toml.bak
  popd >/dev/null
}

put_secret() {  # put_secret <dir> <NAME> <value>
  ( cd "$1" && printf '%s' "$3" | npx wrangler secret put "$2" "${ENV_FLAG[@]}" >/dev/null )
}

deploy() {  # deploy <dir> → echoes the deployed URL
  ( cd "$1" && npx wrangler deploy "${ENV_FLAG[@]}" 2>/dev/null \
      | grep -o 'https://[^ ]*workers\.dev' | head -1 )
}

# ── 1+2. KV + shared secret ─────────────────────────────────────────────────

for pair in "backend auctionbaby-payout" "consumables auctionbaby-consumables"; do
  set -- $pair; ensure_kv "$1" "$2"
done

APP_SHARED_SECRET="${APP_SHARED_SECRET:-$(openssl rand -hex 32)}"
say "Installing shared APP_SHARED_SECRET on both workers…"
put_secret backend     APP_SHARED_SECRET "$APP_SHARED_SECRET"
put_secret consumables APP_SHARED_SECRET "$APP_SHARED_SECRET"

# ── 3. Stripe key ────────────────────────────────────────────────────────────

say "Installing STRIPE_SECRET_KEY on both workers…"
put_secret backend     STRIPE_SECRET_KEY "$STRIPE_SECRET_KEY"
put_secret consumables STRIPE_SECRET_KEY "$STRIPE_SECRET_KEY"

# ── 4. Deploy ────────────────────────────────────────────────────────────────

say "Deploying auctionbaby-payout${ENV_SUFFIX}…"
PAYOUT_URL=$(deploy backend)
say "Deploying auctionbaby-consumables${ENV_SUFFIX}…"
CONSUMABLES_URL=$(deploy consumables)
echo "  payout:       ${PAYOUT_URL}"
echo "  consumables:  ${CONSUMABLES_URL}"

# ── 5. Stripe webhook for the consumables worker, via the API ───────────────

say "Registering Stripe webhook → ${CONSUMABLES_URL}/webhook…"
WEBHOOK_JSON=$(curl -sS https://api.stripe.com/v1/webhook_endpoints \
  -u "${STRIPE_SECRET_KEY}:" \
  -d "url=${CONSUMABLES_URL}/webhook" \
  -d "enabled_events[]=checkout.session.completed" \
  -d "enabled_events[]=checkout.session.async_payment_succeeded" \
  -d "enabled_events[]=charge.refunded" \
  -d "description=Auction Baby consumables (${ENV})")
WHSEC=$(echo "$WEBHOOK_JSON" | grep -o '"secret": *"whsec_[^"]*"' | sed 's/.*"\(whsec_[^"]*\)".*/\1/')
if [ -n "$WHSEC" ]; then
  put_secret consumables STRIPE_WEBHOOK_SECRET "$WHSEC"
  echo "  webhook registered + signing secret installed."
else
  echo "  ⚠️  Webhook registration failed — response was:"
  echo "$WEBHOOK_JSON" | head -5
  echo "  Create it in the Stripe dashboard and run:"
  echo "    (cd consumables && npx wrangler secret put STRIPE_WEBHOOK_SECRET ${ENV_FLAG[*]:-})"
fi

# ── 6. What's left + the app config ─────────────────────────────────────────

say "Paste into AuctionBaby/Config/Secrets.xcconfig:"
cat <<XC
  AB_WORKER_URL = ${PAYOUT_URL}
  AB_SHARED_SECRET = ${APP_SHARED_SECRET}
  AB_CONSUMABLES_URL = ${CONSUMABLES_URL}
XC

say "Remaining by-hand steps:"
cat <<'REST'
  • App Store Connect → your app → App Store Server Notifications V2:
      point the URL at <payout-url>/webhooks/app-store-server
  • Payout worker's own Stripe webhook (Connect payout/transfer events):
      create in the Stripe dashboard against <payout-url>, then
      (cd backend && npx wrangler secret put STRIPE_WEBHOOK_SECRET [--env staging])
  • Optional operator email: (cd backend && npx wrangler secret put RESEND_API_KEY …)
REST

# ── 7. Smoke tests ───────────────────────────────────────────────────────────

say "Smoke-testing consumables…"
BASE_URL="$CONSUMABLES_URL" APP_SHARED_SECRET="$APP_SHARED_SECRET" ./consumables/smoke-test.sh \
  && echo "consumables ✅" || echo "consumables smoke test FAILED"
if [ -x backend/smoke-test.sh ]; then
  say "Smoke-testing payout…"
  BASE_URL="$PAYOUT_URL" APP_SHARED_SECRET="$APP_SHARED_SECRET" ./backend/smoke-test.sh \
    && echo "payout ✅" || echo "payout smoke test FAILED (check remaining secrets above)"
fi

say "Done. Rebuild the iOS app so Secrets.xcconfig bakes the URLs in."
