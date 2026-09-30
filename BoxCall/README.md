# BoxCall

Social prediction app for opening-weekend box office.

## The first 10 seconds

Open the app and you're standing under a marquee:

- **A scrolling LED ticker** across the top streams live at-the-money CALL and PUT marks for every film now showing, framed by two rows of flickering theater bulbs.
- **Opening Night hero** — the next film to open gets a full-bleed card with its poster, director, implied opening, and a ticking `DAYS : HRS : MIN : SEC` countdown.
- **Weekend Recap** — the Monday after your positions settle, a velvet-red card summarizes wins, losses, net, and your biggest swing. If you came out ahead, confetti.
- **Real upcoming films.** Fifteen studio-announced titles on the fall 2026 → summer 2027 calendar, each with its announced studio, release date, director, cast, and synopsis: *Practical Magic 2*, *Resident Evil*, *Verity*, *The Social Reckoning*, *Clayface*, *The Cat in the Hat*, *The Hunger Games: Sunrise on the Reaping*, *Focker-In-Law*, *Jumanji: Open World*, *Avengers: Doomsday*, *Dune: Part Three*, *Ice Age: Boiling Point*, *Narnia: The Magician's Nephew*, *Sonic the Hedgehog 4*, and *Star Wars: Starfighter*. The built-in provider filters out settled films on launch.
- **Trailers in-app.** Every movie page plays the official trailer inline via a YouTube search-embed — no API key required.
- **Real posters in 30 seconds.** Profile → *Turn on real posters* walks you through pasting a free TMDB key; the catalog re-fetches and every one-sheet blooms in. Key stays on-device.
- **Haptics everywhere.** Medium tap on buy, rigid tap on close, a rising-into-thump Core Haptics celebration on big wins, error on losses, double-thump on badges.
- **Streak fire.** A pulsing flame badge next to your handle when you've won consecutive weeks. Users trade play-money **Call / Put contracts** on upcoming movies, and their calls become **posts in the feed** alongside BoxCall's simulated league of automated traders (each marked SIM in the app — there is no server, so no other real players appear).

No real money changes hands. Winning is measured in **status**: total profit, trader rank, the homepage review spotlight, badges, and season titles.

## The reward stack

Winning gets you:

- **Total profit** — the one leaderboard number. Only settled or sold trades move it; the weekly reset and subscriptions never do.
- **The review spotlight** — the top 5 by total profit get their latest movie review on the Marquee home screen; #1 leads it.
- **Trader ranks**, earned only by best total profit (never bought, never lost in a bad week):
  - Analyst (250 RC): verified checkmark
  - Insider (750): gold username
  - Producer (1,500): rank ring around the avatar
  - Studio Head (3,000): gold frame on hot takes in the feed
  - Legend (7,500): Legend rosette on the leaderboard
- **Season Oracle** — #1 in total profit when a quarter ends gets "Oracle · Fall 2026" on the trophy shelf
- **Badges** for specific feats — Bomb Caller, Rocket, Contrarian, Sniper (5 in a row)
- **Streaks** — winning weeks in a row, with badges at 3 and 10

The core loop: bold call → it hits → profit → rank and leaderboard climb → your review goes up on the home screen.

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
    │   ├── User.swift              # profit, rank, streak, badges, trophies
    │   ├── Rewards.swift           # Tier + Badge catalog
    │   └── SocialPost.swift        # posts, comments, outcomes
    ├── Services/
    │   ├── MarketService.swift     # verified catalog + chain pricing
    │   ├── PortfolioService.swift  # buy/close/settle
    │   ├── RewardsService.swift    # rank-ups, badges, streaks
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

Or open Xcode → File → New → Project → iOS App named `BoxCall`, then drop `BoxCall/BoxCall/` sources into the target. Deployment target: iOS 17. The bundled movie slate contains verified announced releases; market prices and social activity are simulated. Hit "Simulate opening weekends" in the Portfolio tab to trigger settlements, badges, and outcome banners on your feed posts.

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
- `TMDBMovieProvider` — free official /movie/upcoming, called directly from the client when a key is set (titles, posters, dates, genres)
- `PublishedCatalogProvider` — `upcoming.json` from the BoxCall data feed, rebuilt by the BoxCall Data workflow from the Box Office Mojo and The Numbers release calendars
- `VerifiedMovieProvider` — hand-curated studio-announced slate, bundled so the app is full offline

Dedup by title key (case, accent and punctuation folded). Later sources win the tie, except that a live calendar's release date beats the bundled one, and missing posters or synopses are filled from the other sources. The merged catalog is saved on device, so a film you hold stays listed until it settles.

**Tracking sources** — `TrackingDataSource` protocol; `CompositeTrackingSource` tries in order:
- `TradeProjectionTrackingSource` — the opening range the trades published, blended toward the app's estimate as it ages
- `AlgorithmicTrackingSource` — always-on fallback: the movie's own estimate from the data feed

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

This makes the chart look *chart-shaped*: bouncing off levels, mean-reverting inside a band, and only breaking out when real flow (a user trade or shifted sentiment) overpowers the MM.

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

**Weekly cycle** (`RefillClock.swift` / `WeeklyReset`, `PortfolioService.applyWeeklyCycle()`):
- **Friday:** a movie opens and trading on it locks (`Movie.isTradingOpen`). Movies that haven't opened keep trading.
- **Sunday 00:00 local:** the week's stake is taken back; profit is kept as cash. Unfilled limit orders are refunded first. Open positions are never closed — any stake riding on them becomes `stakeOwed`.
- **Sunday afternoon:** studios report weekend estimates; the BoxCall Data workflow publishes them within the hour and the app settles opening-weekend trades on that figure (frozen, so everyone settles on the same number).
- **Monday 00:00 local:** a fresh 1,000 RC stake lands, so a player who lost everything is back in.
- A position that was open at a reset repays up to its cost toward `stakeOwed` from its proceeds; profit above cost is kept, and a losing carried trade owes nothing. This stops a player dodging the reset by parking the stake in an unreleased movie.
- Missed a week? On next launch you get exactly one reset and one stake — never a stacked backlog.

**The three ways you can lose coins** — spelled out with numbers in `LearnView` (Losing Coins section):
1. **Contract expires worthless.** Your Call finishes below the strike (or Put finishes above) → you lose the full premium × quantity. Max loss, capped.
2. **Close early at a worse mark.** Market moved against you; you close to cap the loss. You lose the difference between entry and current mark × quantity.
3. **Open position red.** Mark dropped but you're still holding. No coin lost yet — realizes only on close or settlement.

**Zero-balance UX:**
- Trading pauses; you can still watch, read the feed, comment, and write reviews.
- Push notification fires the moment a settlement drops the balance to zero: "You're out of Reel Coins. Trading pauses until Monday morning."
- Low-balance banner shows a live countdown ("Fresh stake: **Monday** · in 2d 14h") on Portfolio + Slate.
- Balance card in Portfolio shows the Sunday reset countdown and Monday's stake.
- TradeSheet risk card includes the countdown in the loss warning.

## Risk-awareness (you can lose coins)

Every entry point sets expectations clearly:

- **Trade Sheet risk card** — a red-bordered "You could lose up to X RC" section spelling out exactly which opening-weekend outcome makes the contract expire worthless, plus a reminder that coins refill weekly.
- **Onboarding slide** — the play-money-real-status slide now explicitly says losing trades cost coins and names the premium as the max loss.
- **Low-balance banner** on Portfolio and Slate — appears when balance drops under 100 RC. Shows the countdown to Monday's stake. A separate "you're out" state kicks in at 0.
- **Insufficient-funds error** — friendly wording that suggests reducing quantity or waiting for Monday's stake.
- **LearnView "Losing coins" section** — dedicated block covering: max loss = premium, mark can drop pre-settlement, you never go negative, weekly refills are automatic, and none of this is real money.
- **Profile deep link** — "Losing coins" is one of the featured Learn links, alongside Calls and Puts.

## Fairness + monetization (3 IAP tiers)

**Every account trades the same bankroll**: a 1,000 RC stake every week, free or paid. Profit only measures skill when nobody can buy a bigger bankroll, so no plan adds coins. `StartingGrant.reelCoins` is the single source of truth.

Subscriptions sell tools and a name badge. Trader ranks, leaderboard spots and the review spotlight stay earned by trading profit.

| Membership | Price | Badge | Tools |
|---|---|---|---|
| **Free** | — | — | 1 limit order |
| **Backstage** | $3.99/mo | ticket | 24-hour early access to new markets, 3 limit orders |
| **Producer's Pass** | $9.99/mo | star | Portfolio performance stats, 10 limit orders |
| **Mogul** | $24.99/mo | crown | Unlimited limit orders, plus everything in Producer's Pass |

Implementation:
- `Models/Membership.swift` — the four cases with pricing, perks, colors, product IDs
- `Services/StoreService.swift` — StoreKit 2 wrapper: loads products, drives purchase, listens to `Transaction.updates` for renewals + revocations, restores purchases, falls back to a demo activation if products can't be loaded
- `Products.storekit` — StoreKit Configuration file attached to the scheme so the paywall works out-of-the-box in Xcode without App Store Connect setup
- `Views/PaywallView.swift` — three tier cards with per-tier accent colors and a fairness banner reminding users that status is not for sale
- Profile membership card, Slate coin-balance chip, and weekly-allowance calculation all pull from `user.membership.weeklyAllowance` — a downgrade flips everything back to the free rate immediately

## Dynamic implied consensus

The "opening weekend estimate" is no longer a static tracker number — it's a **live crowd forecast** derived from the market itself. Every buy and sell shifts a per-movie sentiment multiplier; the implied consensus is `base × sentiment`. Users see the current implied number with a `%` delta arrow vs the original tracker, plus a live sparkline of how the crowd forecast has been drifting. Same treatment on the Slate list, Movie Detail card, and the Trade Sheet's "if tracks…" scenario.

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
- **No invented news.** Nothing in the market produces text about a real film. Ambient sentiment noise moves numbers only; the "What moved it" list shows real inputs (your trades, Hot Takes, reviews, feed signals).
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

- **Push notifications** (local now, APNs later): settlement results, badge unlocks, tier promotions, voided markets, and an evening-before reminder (6 PM, before trading locks) for each film you hold. In-app inbox with an unread bell on the Feed nav bar.
- **Copy-trade**: any feed post has a "Copy call" button that pops the TradeSheet pre-filled with the same movie / side / strike / quantity, priced at the current chain premium. Disabled once the movie settles.

## Next steps

1. **Live data**: enrich `MarketService.loadVerifiedCatalog()` with a backend that pulls upcoming releases from TMDB and tracking numbers from Deadline / Box Office Mojo / The Numbers.
2. **Server-side settlement**: Monday job fetches Friday–Sunday grosses and pays out positions.
3. **APNs**: replace local notifications with server-side pushes so settlement / social events fire even when the app is closed for weeks.
4. **Season resets** every 12 weeks with an Oracle crowning ceremony.
5. **Deep links** from notifications straight to the relevant movie / post / profile.
