# Reply to App Review: guidelines 4.3(a), 4.3(b), 4.2.6

Paste the reply below into App Store Connect > App Review (Resolution Center). Do not resubmit the build; Apple asked for a reply only.

Before sending:

1. Fill every `[BRACKETED]` item. Only you know these facts. Don't send a placeholder, and don't invent testers or feedback.
2. Question 4 is filled in from your testing. Check that every line matches what you did, especially the devices.
3. If the reply box won't take the full text, attach it as a PDF, or split it into two messages (questions 1–4, then 5–9).

---

Hello App Review team,

Thank you for the review. We believe BoxCall meets guidelines 4.3(a), 4.3(b) and 4.2.6. Our answers are numbered to match your questions.

**1. What the app does and the problem it solves**

BoxCall is a free, play-money game. Movie fans predict each new film's U.S. opening weekend by trading simple options contracts on it.

For every film opening in the next few weeks, the app sets out a ladder of five strike levels around the predicted opening, for example $40M, $45M, $50M, $55M and $60M. A player buys a "Call" if they think the film will open above a strike, or a "Put" if they think it will open below. They pay with Reel Coins, a play currency that cannot be bought as a balance, cashed out or transferred.

Contract prices move during the week with the data the app collects:
- tracking forecasts
- trailer activity
- social sentiment
- how close the film is to release

Buys fill at the ask and early closes fill at the bid, as in a real options market. The app shows payoff charts and "You win if… / You lose if…" scenarios before every trade.

The weekly cycle:
- Trading on a film locks at midnight on its opening day.
- On Sunday afternoon, every open position settles against the studios' reported domestic opening estimate. A background task settles positions and sends the payout notice even when the app is closed.
- Every Monday each player gets a fresh 1,000-coin stake. A bad week never locks anyone out.

It solves two problems:
- Fans who follow box office have no quick, weekly, free way to put their read on an opening to the test and see how it compares with other players.
- People curious about options (strikes, calls, puts, bid/ask spreads, time decay) usually can only learn with real money. BoxCall teaches those mechanics with no financial risk, using a subject players already have intuition for. A built-in tutorial and a full in-app guide explain each concept using that week's real films and real past results.

**2. Intended user**

- Movie fans aged 13 and over who follow release calendars, trailers and weekend box-office reports. They read box-office coverage, argue about whether a film will "open big", and want a scoreboard for being right.
- Students and adults who want to understand how options work before ever touching a real brokerage account. BoxCall gives them a safe, concrete practice ground.
- Casual competitive players who want a short weekly loop: one decision per film, results by Sunday, a leaderboard reset every week.

It is not aimed at gamblers. Nothing of value can be won, and there are no real-money or prize features.

**3. The gap BoxCall fills**

To our knowledge, existing movie-prediction products work quite differently:
- Long-running web "movie stock" exchanges hold positions for months on a film's total gross, and are not built around a mobile weekly loop.
- Fantasy box-office leagues are draft-based and run for a whole season. They usually need a group of friends to organize the league.
- Real-money prediction and event-contract markets are restricted to adults, are regulated, and put money at risk.

BoxCall's combination is, as far as we can find, not offered elsewhere:
- **Options mechanics** (strike ladders, calls and puts, bid/ask, payoff charts) applied to movie openings, not a single over/under pick or a "stock" price.
- **Weekly settlement on real data.** Every position resolves the same weekend, against the studios' reported Sunday estimate, which our own pipeline collects from public box-office reports.
- **Free and risk-free for ages 13+.** No real money, no coin purchases, and a fresh stake every Monday.
- **Teaching built in.** The tutorial, guide and trade screens explain each options concept using that week's films.
- **Native Apple features:** a home-screen widget, Live Activities, an Apple Watch app and complication, and background settlement with a payout notification.

**4. Beta testing**

We did not use TestFlight. Instead the developer, Mike Valasek, tested the app thoroughly for more than a month before submission:
- daily use on physical iPhones and an Apple Watch, plus the iOS Simulator
- the full weekly cycle of buying, closing early, Sunday settlement and the Monday stake reset
- automated unit and UI tests that run on every build, covering pricing, settlement and portfolio flows
- a separate automated test suite for the data pipeline that supplies the movie slate and results

Feedback from that testing that changed the production build:
- **Tutorial:** wording was confusing about prices. We rewrote it to say plainly that buys fill at the ask and closing early sells at the bid. We also replaced made-up examples with a real past result (Resident Evil, $60.1M opening).
- **Settlement:** Sunday results only settled once the player opened the app. We added a background refresh task that checks every film on the slate, settles Sunday results and sends the payout notice even when the app is closed.
- **Data:** box-office chart "totals" rows could be mistaken for a film's result. The data pipeline now rejects those rows, with automated tests covering it.
- **Watch and widget:** a build error appeared in the watch and widget targets. We fixed it, and every build now has to pass a clean automated build and test run before it can be uploaded.

**5. Standalone or part of a suite**

BoxCall is a standalone product. [IF YOU HAVE OTHER LIVE OR PENDING APPS ON THIS ACCOUNT, NAME EACH ONE AND SAY WHAT IT DOES IN ONE LINE, e.g. "Our account also has [App name], a [category] app for [purpose]. It has nothing to do with movies, games or trading." IF NOT, WRITE: "It is the only app on our developer account."]

**6. Could it be an in-app purchase in another of our apps?**

No. [IF OTHER APPS EXIST:] None of our other apps involve movies, games, box office or trading, so BoxCall would be an unrelated feature inside any of them. It has its own audience (movie fans and options learners), its own weekly data feed, and its own Apple Watch, widget and Live Activity experience. [IF NO OTHER APPS: "We have no other app it could be added to."]

**7. Code, frameworks or assets shared with our other apps**

No. BoxCall's binary is built only from its own project: about 110 Swift source files written for this app, its own asset catalog and icons, and Apple system frameworks (SwiftUI, StoreKit 2, WidgetKit, ActivityKit, WatchConnectivity, AuthenticationServices, UserNotifications, BackgroundTasks, CoreHaptics). It contains no shared modules, packages or assets from any other app on our account, and no third-party SDKs.

**8. Codebase, SDK or content library shared with any third-party app**

No. BoxCall uses no third-party SDK or template. Its data comes from:
- Our own data pipeline, which compiles the release slate and reported opening-weekend grosses from public box-office reports and publishes them as JSON files that the app reads.
- The TMDB API (optional), only for posters and film details, with the required attribution in Profile > Data sources.
- Links to official trailers on YouTube.

All game logic is original to BoxCall: contract pricing, the strike ladder, the bid/ask spread, settlement, the weekly stake cycle, the leaderboard, the tutorial, and the watch and widget experiences.

**9. Created for a client, partner or third party?**

No. BoxCall was conceived, designed and built by its developer, Mike Valasek, who also provides all of its content and branding. It was not built from a commercial template or an app-generation service, and it is not submitted on anyone else's behalf.

Thank you for taking another look. We're happy to provide a new screen recording or a TestFlight build if that helps.

Mike Valasek
Developer, BoxCall
[YOUR EMAIL]

---

## Notes for you (don't send)

- **Question 4:** Apple sometimes follows up by asking for tester feedback, so the answer lists specific changes your testing caused. Every item is a real fix in this repo. If other people also tried the app (friends, family), add a line saying who they were and roughly how many. Apple may ask again later, and it sometimes suggests a TestFlight beta.
- **About question 9 and AI-assisted coding:** guideline 4.2.6 is about commercial templates and "app generation services" that publish apps for clients. Writing the app yourself with an AI coding assistant is not that, so "No" is accurate. Don't claim every line was hand-typed. If Apple asks directly how the app was built, answer plainly.
- **About question 3:** the competitor descriptions are deliberately general ("to our knowledge"). Check them against what is actually on the App Store today before sending, and name specific apps only if you are sure of the facts.
- **About question 7:** the same developer team ID is used in this repo for other projects (AIMarketplace/MetaBro, CodeGenie, Watchfighter). BoxCall's Xcode project includes none of their source, so the "No" holds. List any of them that are live or in review under question 5.
