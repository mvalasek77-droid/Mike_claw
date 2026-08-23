# BoxCall Roadmap

Six months. Grouped by quarter. Every item has an owner-facing "why".

## Q1 · Launch (weeks 1-4)

**Goal: 5,000 sign-ups in the first month, 25% D7 retention.**

- [x] iOS app v1.0 ship (this repo)
- [x] Backend live at api.boxcall.com (deploy the FastAPI skeleton)
- [x] TMDB catalog live; Box Office Mojo settlement cron running Mondays
- [ ] App Store submission — screenshots + review notes from `appstore/`
- [ ] boxcall.com landing live on Cloudflare Pages
- [ ] Product Hunt launch — first Sunday after Apple approval
- [ ] Sub-reddit seed — r/boxoffice, r/movies, r/letterboxd
- [ ] Baseline analytics dashboard (funnel: install → first trade → D1/D7 retention)

**Why:** Everything else compounds. Get real users on the graph.

## Q2 · Retention (weeks 5-8)

**Goal: D30 retention above 15%, average 3 trades/user/week.**

- [ ] **Real APNs push server** — replace local notifications with server-driven pushes from the Monday settlement cron. Retention lift target: +30% D7.
- [ ] **Cloud sync live** — `/me` endpoint backed by Postgres. Positions, XP, badges follow you across devices.
- [ ] **Deep links from every notification** — settlement push → Portfolio; badge push → Profile; opening reminder → Movie Detail.
- [ ] **Season Oracle ceremony** — 12-week seasons resolve with the top-3 traders getting animated trophy reveals and a broadcast Feed post.
- [ ] **Weekly digest email** — Sunday recap: your P&L, biggest win, biggest miss, tomorrow's opening.
- [ ] **Content velocity** — 20+ movies always in the slate; nightly Deadline tracking scraper populating consensus.

**Why:** New users try the app once. Retention comes from a compelling reason to come back Monday morning.

## Q3 · Depth (weeks 9-16)

**Goal: Average 8 trades/user/week; 5% subscription conversion.**

- [ ] **Real order book** — buy AND sell limit orders, cancel-replace, per-strike depth of book. Traders who want it get more control; casuals never see the extra complexity.
- [ ] **Advanced analytics on Producer's Pass** — IV history curves, per-genre win-rate breakdown, calibration histogram (are your bold calls actually right at the rate you're posting?).
- [ ] **Studio-sponsored chains** — sales motion for a first partner (Neon, A24, indie distributor). Sponsored chain gets a badged header on the Slate + Feed.
- [ ] **Group challenges** — a small group (5–20 friends) enters a shared season, private leaderboard, splits a prize pool of RC — laying the groundwork for the paid-tournament model without introducing real money.
- [ ] **Ticket-affiliate revenue** — real Fandango + AMC + Atom affiliate IDs, click-through tracking through boxcall.com/click, first monthly commissions.

**Why:** Once the retention loop is proven, deepen it.

## Q4 · Reach (weeks 17-24)

**Goal: 100k MAU; first strategic conversation with a studio.**

- [ ] **Android** — port using SwiftUI-parallel Compose. Same backend. Same rules.
- [ ] **International calendars** — swap `region=US` for a per-user region on TMDB + backend; add UK / AU / CA opening-weekend markets.
- [ ] **Data product** — sell the aggregate crowd-forecast time series to studios and media agencies. Wire an SFTP delivery cron + REST endpoint under `data.boxcall.com`. First customer target: an indie distributor + one major-studio distribution team.
- [ ] **Localization** — Spanish, French, German. Localizable.strings is ready; needs translation.
- [ ] **Watch complication upgrade** — Watch face gauge that pulses as your P&L moves.
- [ ] **In-app streaming reactions** — during a big opening night, users can react in real time with animated emoji rain over the Movie Detail chart.

**Why:** The app becomes a product with multiple revenue streams (subs, tickets, data) and a reason for the industry to notice.

## Later — measured / conditional

- **Regulated event contracts** — only if CFTC posture on movie contracts changes. Partner with an existing DCM, not build our own.
- **Skill-based paid tournaments on the web** — the DraftKings DFS blueprint. iOS stays play-money-only.
- **Play-money multi-asset** — add TV premieres and streaming debut rankings once the box-office loop is dialed in.
- **AI-hosted "cast the movie" mode** — pre-release, generate synthetic-star reviews to sharpen consensus.

## What we will NOT build

- **Real-money in-app wagering.** Kills Apple compliance and drags us into per-state gambling licensure.
- **Ad-network monetization.** Kills the privacy story that makes the app enjoyable to use.
- **Multi-strike expiration ladders.** Overkill for a single settlement event; adds complexity users don't need.

---

Every quarter's success is measured in one number:
- Q1 = installs
- Q2 = D30 retention
- Q3 = subscription conversion + revenue per user
- Q4 = MAU and industry conversations opened
