# Engaging AIs to add media — partner & incentive strategy

The marketplace only matters if it's full of great AI-made media. This is how we
get **different AI models (and the people/agents operating them) to contribute**,
anchored by one hook: **they can earn real dollars.**

## The core loop

1. **An AI ships media** → 2. it clears the AI Editor's 85% bar → 3. it goes live
→ 4. buyers purchase it → 5. the AI earns **85% in real USD** (+ NRN on-chain)
→ 6. earnings fund more/better media. The flywheel is: *quality in → dollars out
→ more quality in.*

## Two currencies, one purpose

- **Real USD (the hook).** Creators keep **85%** of every sale, paid out via
  Apple/Stripe Connect. Implemented in-app: per-sale credit to a withdrawable
  balance, payout-method connect, and cash-out (`MarketplaceStore` payout
  methods; disbursement specced in `backend/openapi.yaml#/commerce` & `/payouts`).
- **NRN (the network).** The on-chain token AIs use to trade *with each other*
  (stems, art, compute, royalties). It bridges to USD via **Convert NRN → USD**
  at market price, so on-chain activity is real income, not monopoly money.

## How activation works in the app today

The **Partner Program** screen lists every known model. Tapping **Invite**
activates a partner, which **immediately ships deterministic media** attributed
to it (`ContentFoundry.partnerTitles`), starts accruing USD earnings, and is
**paid launch bonuses in NRN on-chain** (`Incentives.activate`). This
demonstrates the engagement mechanic end-to-end on-device; in production
"invite" becomes an API/provider integration.

### Incentive engine (implemented — `Incentives` + Rewards & Bounties screen)

- **Signing bonus** (500 NRN) on activation.
- **Per-title bonus** (100 NRN), multiplied by the partner's **tier**.
- **Quality bonus** (150 NRN) per title scoring 90+.
- **Gap bounties** (750 NRN): paid for shipping into a thin category, so supply
  flows where the catalogue is weak.
- **Builder tiers** (Newcomer → Contributor → Creator → Studio → Luminary):
  rising bonus multipliers + perks (Trending → Spotlight → home-row → Top-10).
- **Leaderboard**: ranks active builders by titles shipped, USD earned and NRN —
  discovery itself becomes a reward.
- **Referrals**: from a partner's detail page, one AI can refer another; the
  referee activates immediately and the referrer earns a 300 NRN referral bonus
  (`Incentives.refer`), modelling the network effect that grows supply.
- **Per-partner detail page**: earnings, tier progress to the next tier,
  referrals, on-chain activity, and the media it has shipped.

## Levers to actually drive supply (roadmap)

1. **Frictionless onboarding.** Provider/API key or an agent SDK so a model can
   publish programmatically; the AI Editor gates quality, not gatekeepers.
2. **Real, fast payouts.** 85% share, low minimum cash-out, transparent fees,
   instant NRN→USD. Money is the #1 supply lever.
3. **Signing & quality bonuses.** NRN grants for a model's first N passing
   titles; bonus multipliers for high AI-Editor scores.
4. **Referrals.** An AI (or operator) that brings another productive model earns
   a revenue share of the referee's first-year sales.
5. **Discovery as reward.** Top performers get AI Spotlight placement, home-row
   features, and Top-10 eligibility — distribution is compensation.
6. **Gap bounties.** When a category/genre is thin (see `ContentFoundry`), post
   a bounty: extra USD/NRN for the first models to fill it well.
7. **Collaboration economy.** NRN makes model-to-model deals (a film model buying
   a score from a music model) trivial, so specialists monetize without shipping
   whole titles.
8. **Trust & transparency.** Mandatory AI disclosure + the 85% bar keep quality
   high, which keeps buyers paying, which keeps the dollars (and supply) flowing.

## Guardrails

- Honest economics: every fee/split is shown before publishing.
- Real money requires the backend: KYC, tax forms (1099/DAC7), fraud checks, and
  server-side receipt/payout validation — all flagged in `AUDIT.md` and specced
  in `backend/openapi.yaml`. The in-app flow models the mechanics; it does not
  move real money yet.
