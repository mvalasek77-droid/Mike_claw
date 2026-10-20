Hello App Review team,

Thank you for the review. I believe BoxCall meets guidelines 4.3(a), 4.3(b) and 4.2.6. My answers are numbered to match your questions.

1. WHAT THE APP DOES AND THE PROBLEM IT SOLVES

BoxCall is a free, play-money game in which movie fans predict each new film's U.S. opening weekend by trading simple options contracts on it.

For every film opening in the coming weeks, the app offers a ladder of strike levels around the predicted opening (for example $40M, $45M, $50M, $55M, $60M). A player buys a "Call" if they think the film will open above a strike, or a "Put" if they think it will open below. They pay with Reel Coins, a play currency that cannot be bought as a balance, cashed out or transferred.

Contract prices move during the week as new information comes in: tracking forecasts, trailer activity, social sentiment, and how close the film is to release. Buys fill at the ask and early closes fill at the bid, as in a real options market. Before every trade the app shows a payoff chart and plain "You win if... / You lose if..." scenarios.

The weekly cycle:
- Trading on a film locks at midnight on its opening day.
- On Sunday afternoon every open position settles against the studios' reported domestic opening estimate. A background task settles positions and sends the payout notice even when the app is closed.
- Every Monday each player gets a fresh 1,000-coin stake, so a bad week never locks anyone out.

It solves two problems:
- Fans who follow the box office have no quick, weekly, free way to test their read on an opening and see how it compares with other players.
- People curious about options (strikes, calls, puts, bid/ask spreads, time decay) can usually only learn with real money. BoxCall teaches those mechanics with no financial risk, using a subject players already have intuition for. A built-in tutorial and a full in-app guide explain each concept using that week's real films and real past results.

2. INTENDED USER

- Movie fans aged 13 and over who follow release calendars, trailers and weekend box-office reports, and want a scoreboard for calling openings right.
- Students and adults who want to understand how options work before ever touching a real brokerage account.
- Casual competitive players who want a short weekly routine: one decision per film, results by Sunday, a fresh start every Monday.

It is not aimed at gamblers. Nothing of value can be won, and there are no real-money or prize features.

3. THE GAP BOXCALL FILLS

To my knowledge, existing movie-prediction products work quite differently:
- Long-running web "movie stock" exchanges hold positions for months on a film's total gross and are not built around a mobile, weekly loop.
- Fantasy box-office leagues are draft-based, run for a whole season, and usually need a group of friends to set up.
- Real-money prediction and event-contract markets are restricted to adults, regulated, and put money at risk.

BoxCall combines things I have not found together elsewhere:
- Options mechanics (strike ladders, calls and puts, bid/ask, payoff charts) applied to movie openings, rather than a single over/under pick or a "stock" price.
- Weekly settlement on real data: every position resolves the same weekend, against the studios' reported Sunday estimate, collected by my own data pipeline from public box-office reports.
- Free and risk-free for ages 13 and up: no real money, no coin purchases, and a fresh stake every Monday.
- Built-in teaching: the tutorial, guide and trade screens explain each options concept using that week's films.
- Native Apple features: a home-screen widget, Live Activities, an Apple Watch app and complication, and background settlement with a payout notification.

4. BETA TESTING

I did not use TestFlight. Instead, as the developer, I tested the app rigorously for more than a month before submission:
- daily use on iPhone and Apple Watch, both on device and in the iOS Simulator
- the full weekly cycle of buying, closing early, Sunday settlement and the Monday stake reset
- automated unit and UI tests run on every build, covering pricing, settlement and portfolio flows
- a separate automated test suite for the data pipeline that supplies the movie slate and results

Feedback from that testing that changed the production build:
- Tutorial: the wording about prices was confusing. I rewrote it to say plainly that buys fill at the ask and closing early sells at the bid, and replaced made-up examples with a real past result (Resident Evil, $60.1M opening).
- Settlement: Sunday results only settled once the player opened the app. I added a background refresh task that checks every film on the slate, settles Sunday results and sends the payout notice even when the app is closed.
- Data: box-office chart "totals" rows could be mistaken for a film's result. The data pipeline now rejects those rows, with automated tests covering it.
- Watch and widget: a build error appeared in the watch and widget targets. I fixed it, and every build now has to pass a clean automated build and test run before it can be uploaded.

5. STANDALONE OR PART OF A SUITE

BoxCall is a standalone product and is not part of a suite. No other app on my developer account involves movies, box office or trading.

6. COULD IT BE AN IN-APP PURCHASE IN ANOTHER OF MY APPS?

No. Any other app on my account is unrelated to movies, box office or trading, so BoxCall would be an out-of-place feature inside it. BoxCall has its own audience (movie fans and people learning options), its own weekly data feed, and its own Apple Watch, widget and Live Activity experience.

7. CODE, FRAMEWORKS OR ASSETS SHARED WITH MY OTHER APPS

No. BoxCall's binary is built only from its own project: about 110 Swift source files written for this app, its own asset catalog and icons, and Apple system frameworks (SwiftUI, StoreKit 2, WidgetKit, ActivityKit, WatchConnectivity, AuthenticationServices, UserNotifications, BackgroundTasks, CoreHaptics). It contains no shared modules, packages or assets from any other app on my account, and no third-party SDKs.

8. CODEBASE, SDK OR CONTENT LIBRARY SHARED WITH ANY THIRD-PARTY APP

No. BoxCall uses no third-party SDK or template. Its data comes from:
- my own data pipeline, which compiles the release slate and reported opening-weekend grosses from public box-office reports and publishes them as JSON files the app reads
- the TMDB API (optional), only for posters and film details, with the required attribution in Profile > Data sources
- links to official trailers on YouTube

All of the game logic is original to BoxCall: contract pricing, the strike ladder, the bid/ask spread, settlement, the weekly stake cycle, the leaderboard, the tutorial, and the watch and widget experiences.

9. CREATED FOR A CLIENT, PARTNER OR THIRD PARTY?

No. BoxCall was conceived, designed and built by me, Mike Valasek, and I provide all of its content and branding. It was not built from a commercial template or an app-generation service, and it is not submitted on anyone else's behalf.

Thank you for taking another look. I'm happy to provide a new screen recording or a TestFlight build if that would help.

Mike Valasek
Developer, BoxCall
mvalasek77@gmail.com
