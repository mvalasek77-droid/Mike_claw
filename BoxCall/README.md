# BoxCall

Play-money iOS app for trading **Call / Put contracts on opening-weekend box office**. Like an options chain for movies about to be released — every upcoming film has a live consensus opening-weekend gross, and you buy Calls (bullish) or Puts (bearish) at any strike on the chain.

## Concept

- Every movie has an **options chain** with 5 strikes above and 5 below its consensus opening.
- **Call payoff**: `max(actual − strike, 0) × multiplier × qty`
- **Put payoff**: `max(strike − actual, 0) × multiplier × qty`
- Positions settle Monday morning against the reported opening-weekend gross (Box Office Mojo would be the production data source).
- Currency is **Reel Coins**, refilled 500 per week. No real money, no in-app purchase for balances — this keeps the app inside Apple's guideline 5.3 (Gaming, Gambling & Lotteries) as a social prediction game rather than a gambling product.

## How it's different from Kalshi

Kalshi trades **YES/NO binary event contracts** at a single fixed strike per question. BoxCall trades a **continuous-payoff options chain** — you choose the strike, payoff scales linearly with the actual number, and both Call and Put sides trade at each strike. It feels like an equity options screen, not a prediction market.

## Structure

```
BoxCall/
├── project.yml                # xcodegen spec
└── BoxCall/
    ├── BoxCallApp.swift       # entry
    ├── Models/                # Movie, Contract, Position, User
    ├── Services/              # MarketService (mock chain), PortfolioService
    ├── Views/                 # RootView (tabs), Slate, Detail, TradeSheet, Portfolio, Leaderboard
    └── Assets.xcassets
```

## Open in Xcode

If you have [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd BoxCall
brew install xcodegen        # first time only
xcodegen generate
open BoxCall.xcodeproj
```

Otherwise open Xcode → File → New → Project → iOS App, name it `BoxCall`, then drop the `BoxCall/BoxCall/` sources into the target.

Deployment target: iOS 17. Everything runs on mock data in-memory — no backend required to try the flow.

## Next steps

1. **Real data**: swap `MarketService.loadMockCatalog()` for a call to a backend that pulls upcoming releases from TMDB and tracking numbers from Deadline / Box Office Mojo / The Numbers.
2. **Server-side settlement**: run a Monday job that fetches Friday–Sunday grosses and pays out positions.
3. **Order book vs mark**: current premiums are algorithmic; a real version would maintain a per-contract order book.
4. **Social**: comments per movie, share-my-play cards for iMessage.
5. **App Store compliance review**: draft privacy manifest, add "for entertainment only — no real-money wagering" copy in the About screen and store listing.
