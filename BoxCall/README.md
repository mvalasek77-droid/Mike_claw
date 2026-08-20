# BoxCall

Social prediction app for opening-weekend box office. Users trade play-money **Call / Put contracts** on upcoming movies, and their calls become **posts in a public feed** where the community likes, comments, and follows the sharpest analysts.

No real money changes hands. Winning is measured in **status**: XP, tier progression, badges, followers, and season titles.

## The reward stack

Winning gets you:

- **XP + tier progression** (Rookie → Analyst → Insider → Producer → Studio Head → Oracle)
- **Badges** for specific feats — Bomb Caller, Rocket, Contrarian, Sniper (5 in a row), Seasonal Oracle
- **Followers** — a winning public call brings 3–12 new followers per settlement
- **Social power that unlocks with tier:**
  - Analyst: verified checkmark, post to the public feed
  - Insider: gold username, boost one call/week to the top of a movie's page
  - Producer: create custom markets ("Villeneuve's next opens above $X"), animated avatar frame
  - Studio Head: pin any post 24h, custom victory animation
  - Oracle: seasonal title, quoted on home feed
- **Streaks** (weekly, Duolingo-style) with milestone badges at 3 and 10 weeks
- **Trophy shelf** on profile — "Oracle · Summer 2026"

The core loop: bold call → hits → your post goes viral → you gain followers → tier up → more social power → make bolder calls.

## How it's different from Kalshi

Kalshi trades **YES/NO binary event contracts** at a fixed strike per question. BoxCall trades a **continuous-payoff options chain** — choose the strike, payoff scales linearly with the actual opening-weekend number, both Call and Put sides quoted. Feels like an equity options screen, not a prediction market. And the whole product is designed around the **social feed** — Kalshi has no follow graph, no comments, no reputational status.

## Structure

```
BoxCall/
├── project.yml                     # xcodegen spec
└── BoxCall/
    ├── BoxCallApp.swift            # entry + reward-toast overlay
    ├── Models/
    │   ├── Movie.swift
    │   ├── Contract.swift          # Call/Put + intrinsic payoff
    │   ├── Position.swift
    │   ├── User.swift              # xp, tier, streak, followers, badges, trophies
    │   ├── Rewards.swift           # Tier + Badge catalog
    │   └── SocialPost.swift        # posts, comments, outcomes
    ├── Services/
    │   ├── MarketService.swift     # mock catalog + chain pricing
    │   ├── PortfolioService.swift  # buy/close/settle
    │   ├── RewardsService.swift    # XP, badges, streaks, follower bumps
    │   └── SocialService.swift     # feed, follow, like, comment
    ├── Views/
    │   ├── RootView.swift          # 5 tabs: Feed · Slate · Portfolio · Leaders · Profile
    │   ├── FeedView.swift          # hot takes with likes/comments/follows/outcome banner
    │   ├── MovieListView.swift
    │   ├── MovieDetailView.swift   # options chain
    │   ├── TradeSheet.swift        # place trade + share-as-post toggle
    │   ├── PortfolioView.swift
    │   ├── LeaderboardView.swift   # tiers + verified badges
    │   └── ProfileView.swift       # identity, tier progress, badges, trophies, perks
    └── Assets.xcassets
```

## Open in Xcode

```bash
cd BoxCall
brew install xcodegen        # first time only
xcodegen generate
open BoxCall.xcodeproj
```

Or open Xcode → File → New → Project → iOS App named `BoxCall`, then drop `BoxCall/BoxCall/` sources into the target. Deployment target: iOS 17. Runs entirely on mock data — hit "Simulate opening weekends" in the Portfolio tab to trigger settlements, badges, and outcome banners on your feed posts.

## Monetization (all Apple-compliant)

Since real-money wagering is off the table, revenue stacks:

1. **Premium subscription** ($6.99/mo) — advanced analytics, IV history charts, alerts, priority contest slots. IAP-friendly.
2. **Studio-sponsored chains** — studios pay to promote their release ("Sony presents this chain"). Marketing budget line, not ads budget.
3. **Fandango / AMC A-List affiliate** — every movie page gets a "get tickets" button, 5–8% commission.
4. **Data licensing to studios** — aggregate crowd-forecast time series is a real product. Studios spend millions on tracking (NRG); this could rival it.
5. **In-app video ads** — interstitials between trades.

## Data sources + PriceSetter

Two swappable abstractions handle upcoming releases and the initial premium anchor:

**Upcoming-movies sources** — `MovieDataProvider` protocol; `CompositeMovieProvider` merges multiple:
- `TMDBMovieProvider` — free official /movie/upcoming, called directly from the client (titles, posters, dates, studios, genres)
- `BoxCallBackendUpcomingProvider` — hits `api.boxcall.com/upcoming` which aggregates IMDb Coming Soon, The Numbers release schedule, and Deadline calendars via server-side scrapers. Stubbed today — returns [] until the backend ships — and degrades gracefully so TMDB alone still fills the catalog. Dedup by lowercased title + release-week bucket; later sources win the tie so richer backend metadata beats TMDB baseline.
- `MockMovieProvider` — hand-curated 8-title seed for offline / demo

**Tracking sources** — `TrackingDataSource` protocol; `CompositeTrackingSource` tries in order:
- `BoxCallBackendTrackingSource` — hits `api.boxcall.com/tracking?movie_id=...` which aggregates Deadline + NRG-style pre-release numbers. Stubbed.
- `AlgorithmicTrackingSource` — always-on fallback derived from the movie's own popularity-based estimate.

**PriceSetter** (`Services/PriceSetter.swift`) — pure struct that owns *initial* chain pricing. Given a Movie + Tracking, it emits a 5-strikes-per-side chain of Contracts with theoretical premiums using:
```
intrinsic = max(consensus − K, 0)     for Call
            max(K − consensus, 0)     for Put
moneyness = |consensus − K| / consensus
timeValue = consensus × IV × √(DTE/30) × exp(−moneyness × 1.8) × 0.5
premium   = max(0.25, intrinsic + timeValue)
```
Once the chain is live, `MarketMaker` and user flow take over — PriceSetter's job is done. When a newly added movie's real tracking arrives from the backend, `MarketService.enrichTracking` calls `PriceSetter.chain(...)` again to re-anchor the strikes.

DataSourcesView on the Profile now separates all sources into four sections — Upcoming Releases, Pre-release Tracking, Settlement, and Pricing — each with LIVE / PLANNED status badges so it's obvious what's real today and what's wired to arrive.

## Market makers + support / resistance

Random NPC noise is out; real market-maker behavior is in.

`MarketMaker.swift` computes rolling support and resistance for every contract each tick:
- Rolling window: last 30 price points (~90s at the 3s tick rate)
- **Support** = 20th percentile of the window
- **Resistance** = 80th percentile of the window
- The band between them is the current fair-value zone

Every tick, for every contract:
- If mark is within a `touchZone` of support → MM steps in as a **buyer** (positive demand delta). The next tick reprices the mark up.
- If mark is within a `touchZone` of resistance → MM steps in as a **seller** (negative demand delta). The next tick reprices the mark down.
- **Aggression scales linearly with depth into the zone.** A tiny dip gets a small bid; a full flush past support gets a size buyer.
- Inside the band, small drift noise (±1.5 demand units) keeps the tape alive.

This makes the chart look *chart-shaped*: bouncing off levels, mean-reverting inside a band, and only breaking out when real flow (a user trade, a news event, or shifted sentiment) overpowers the MM.

**Charts (`PriceChart.swift`)** — the Trade Sheet's live chart now draws:
- Green dashed **support** line with `S xx.xx` label to the right
- Red dashed **resistance** line with `R xx.xx` label
- Shaded band between them
- The area under the price curve as before
- A readout row below: two color-coded S/R pills + a "zone" label ("At support — MMs likely bidding" / "At resistance — MMs likely offering" / "Inside the band — free to drift")

`MarketService.srLevels` publishes the current S/R for every contract; any view can look up `market.srLevel(contractId:)` and get the current band.

**LearnView** live-market section now explains the MMs, the S/R bands, and gives the strategy hint: "Enter at support and exit at resistance for the cleanest edges."

## Pre-trade scenario primer

Before a user can hit Buy on any contract, they see the mechanics of THAT specific trade in plain English.

- **`ScenarioPrimer` card** — sits at the top of the Trade Sheet, above the live mark chart, styled with the side's accent color (green for Calls, red for Puts). Contents:
  - "You're going BULLISH / BEARISH" badge
  - "You're buying **N CALLS** at the **$KM** strike on **[Movie]**, for **X RC**."
  - **You WIN if…** — plain-English win condition, break-even value, and the exact RC-per-$1M payoff for the current quantity
  - **You LOSE if…** — the exact miss condition and the exact premium at risk
  - "Max loss is the premium — nothing more, no matter how far it misses."
- **`FirstTradeTutorial` full-screen sheet** — auto-fires the FIRST time a user opens a Call trade (and separately, the first time for a Put) via `@AppStorage("seenPrimerCall")` / `seenPrimerPut`. Three numbered steps, a live payoff chart, and a Skip button. After they hit "Got it — show me the trade", it never fires again for that side.
- **Toolbar menu** — the `?` in the Trade Sheet toolbar is a menu with "How Calls work" (re-opens the tutorial on demand) and "Full guide" (opens LearnView).

The primer answers three questions before every buy: what am I actually buying, what does winning look like in this scenario, and what does losing look like in this scenario.

## Monday reset (how losses actually work)

Losses are real: coins deplete, and if you burn through your balance you can't trade until the reset. But the reset is generous, automatic, and predictable.

**Refill semantics** (`RefillClock.swift`, `PortfolioService.redeemWeeklyIfDue()`):
- Every Monday at 00:00 local time, every account gets its membership's weekly allowance credited.
- Missed a Monday (app closed for a week)? On next launch you get exactly one allowance — never a stacked backlog.
- This mirrors real box-office cadence: opening weekends settle Monday morning; balances do too.

**The three ways you can lose coins** — spelled out with numbers in `LearnView` (Losing Coins section):
1. **Contract expires worthless.** Your Call finishes below the strike (or Put finishes above) → you lose the full premium × quantity. Max loss, capped.
2. **Close early at a worse mark.** Market moved against you; you close to cap the loss. You lose the difference between entry and current mark × quantity.
3. **Open position red.** Mark dropped but you're still holding. No coin lost yet — realizes only on close or settlement.

**Zero-balance UX:**
- Trading pauses; you can still watch, read the feed, comment, and write reviews.
- Push notification fires the moment a settlement drops the balance to zero: "You're out of Reel Coins. Trading pauses until Monday morning."
- Low-balance banner shows a live countdown ("Next refill: **Monday** · in 2d 14h") on Portfolio + Slate.
- Balance card in Portfolio always shows the next Monday reset chip with amount.
- TradeSheet risk card includes the countdown in the loss warning.
- Subscribers get an "Upgrade to skip the wait" CTA — a bigger starting bonus lands immediately.

## Risk-awareness (you can lose coins)

Every entry point sets expectations clearly:

- **Trade Sheet risk card** — a red-bordered "You could lose up to X RC" section spelling out exactly which opening-weekend outcome makes the contract expire worthless, plus a reminder that coins refill weekly.
- **Onboarding slide** — the play-money-real-status slide now explicitly says losing trades cost coins and names the premium as the max loss.
- **Low-balance banner** on Portfolio and Slate — appears when balance drops under 100 RC. Shows countdown to the next refill and offers an Upgrade CTA. A separate "you're out" state kicks in at 0.
- **Insufficient-funds error** — friendly wording that suggests reducing quantity, waiting for the refill, or upgrading.
- **LearnView "Losing coins" section** — dedicated block covering: max loss = premium, mark can drop pre-settlement, you never go negative, weekly refills are automatic, and none of this is real money.
- **Profile deep link** — "Losing coins" is one of the featured Learn links, alongside Calls and Puts.

## Fairness + monetization (3 IAP tiers)

**Every free account starts identical**: 1,000 Reel Coins on sign-up, 500 RC refilled every week, forever. No promo codes, no referral boosts, no way for one free user to start ahead of another. `StartingGrant.reelCoins` is the single source of truth and `PortfolioService.init` enforces it.

Three optional subscription tiers unlock more coins — nothing else. Leaderboards, badges, tier progression (Rookie → Oracle), Featured Critics slots, and every feature stay earned by winning calls, never bought. Status is not for sale.

| Membership | Price | Starting bonus | Weekly allowance | Extras |
|---|---|---|---|---|
| **Free** | — | 0 (1,000 base) | 500 RC | — |
| **Backstage** | $3.99/mo | +5,000 RC | 1,500 RC | Ad-free, extended news ticker |
| **Producer's Pass** | $9.99/mo | +15,000 RC | 4,000 RC | Advanced analytics (IV history, demand heatmap), priority contest slots, profile badge |
| **Mogul** | $24.99/mo | +40,000 RC | 10,000 RC | Create custom markets, pin a post 24h/week, gold avatar frame |

Implementation:
- `Models/Membership.swift` — the four cases with pricing, perks, colors, product IDs
- `Services/StoreService.swift` — StoreKit 2 wrapper: loads products, drives purchase, listens to `Transaction.updates` for renewals + revocations, restores purchases, falls back to a demo activation if products can't be loaded
- `Products.storekit` — StoreKit Configuration file attached to the scheme so the paywall works out-of-the-box in Xcode without App Store Connect setup
- `Views/PaywallView.swift` — three tier cards with per-tier accent colors and a fairness banner reminding users that status is not for sale
- Profile membership card, Slate coin-balance chip, and weekly-allowance calculation all pull from `user.membership.weeklyAllowance` — a downgrade flips everything back to the free rate immediately

## Dynamic implied consensus

The "opening weekend estimate" is no longer a static tracker number — it's a **live crowd forecast** derived from the market itself. Every buy, sell, and news event shifts a per-movie sentiment multiplier; the implied consensus is `base × sentiment`. Users see the current implied number with a `%` delta arrow vs the original tracker, plus a live sparkline of how the crowd forecast has been drifting. Same treatment on the Slate list, Movie Detail card, and the Trade Sheet's "if tracks…" scenario.

## Featured Critics

The top-5 leaderboard performers get their latest **movie review** spotlighted at the top of the Feed:
- **#1 hero card**: full headline + first 4 lines + like count, in an orange-gradient card
- **#2–5**: horizontally scrolling supporting cards ranked with colored rank badges
- **Any user can write a review** from any movie's detail page (⋯ menu → Write a review) — 5-star rating + one-line headline + long-form body
- **Winning traders' opinions become the app's editorial voice** — status → reach

## The live market

Premiums are not static. `MarketService` runs a 3-second tick loop that continuously reprices every contract on every chain:

```
mark = basePremium × exp(demand / liquidity) × movieSentiment × (1 + noise)
```

- **User trades move price directly.** Every `buy` calls `MarketService.recordBuy(contractId:quantity:)` which increments the per-contract demand imbalance; the next tick reprices exponentially. Sells symmetrically pull the mark down. Slippage is intuitive: small trades barely move it, crowd piles create real drift.
- **Background NPC traders** nudge random strikes each tick so the tape is always moving — even when no human is in the app. In a real deployment these are replaced by real user flow and market-maker inventory.
- **Market events** fire ~5% of ticks: a random movie gets a bullish or bearish headline ("Presales spike — 60% ahead of tracking" / "Embargo lifts: reviews weaker than tracking assumed") that shocks the movie's whole chain via a sentiment multiplier — every Call mark moves one way, every Put mark moves the other. Events surface as a news ticker on each movie's page, and users holding open positions on that movie get a push notification.
- **Price history** is stored per-contract (rolling 90 points ≈ 4.5 minutes) and rendered as row sparklines on the chain, and as a full time-series chart with area gradient on the Trade Sheet.
- **Live indicator** — a pulsing green dot marks anywhere the tape is streaming, with the last-tick timestamp so users can tell the market is alive.
- **Mean reversion**: demand drifts back toward zero and sentiment toward 1.0 each tick, so isolated shocks fade if not sustained by continued flow.

## Education layer

Options are unfamiliar to most people. BoxCall teaches the mechanics in three places:

- **First-run onboarding** — 4 slides on launch, complete with a live payoff chart on the Call and Put slides. Users who want more can jump straight into the full guide from the last slide.
- **`LearnView` — the full guide** — 10 sections with headers, worked examples, formula boxes, and hand-drawn `PayoffChart` diagrams. Sections: The Big Idea → Calls → Puts → Strike → Premium & IV → Settlement → Closing Early → Multiplier → Rewards → Glossary. Ends with a plain-English "this is entertainment, no real wagering" disclaimer.
- **Contextual "?" buttons** — top-right of the Movie Detail and Trade Sheet screens, plus a "Learn the game" section on the Profile with deep links directly to Calls, Puts, and the glossary. The Trade Sheet also has an expandable payoff diagram right next to the "if bomb / tracks / blockbuster" table so the shape is visible before you place.

The `PayoffChart` component is a small SwiftUI `Canvas` renderer that draws the classic hockey stick with strike + break-even markers and green/red profit/loss fills. Reusable for future analytics screens.

## Retention & virality loops

- **Push notifications** (local now, APNs later): settlement results, new followers, badge unlocks, tier promotions, 24-hour opening-day reminders scheduled the moment you place a trade. In-app inbox with an unread bell on the Feed nav bar.
- **Copy-trade**: any feed post has a "Copy call" button that pops the TradeSheet pre-filled with the same movie / side / strike / quantity, priced at the current chain premium. Disabled once the movie settles.

## Next steps

1. **Real data**: swap `MarketService.loadMockCatalog()` for a backend that pulls upcoming releases from TMDB and tracking numbers from Deadline / Box Office Mojo / The Numbers.
2. **Server-side settlement**: Monday job fetches Friday–Sunday grosses and pays out positions.
3. **APNs**: replace local notifications with server-side pushes so settlement / social events fire even when the app is closed for weeks.
4. **Season resets** every 12 weeks with an Oracle crowning ceremony.
5. **Deep links** from notifications straight to the relevant movie / post / profile.
