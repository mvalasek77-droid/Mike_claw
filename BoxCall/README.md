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
