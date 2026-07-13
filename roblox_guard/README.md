# RobloxGuard — a parent's early-warning companion for Roblox

RobloxGuard helps parents spot the observable precursors of online grooming on
Roblox — friend-list changes, contacts advertising off-platform handles,
watchlisted experiences, late-night activity — and routes them to the right
response: a conversation with their child, Roblox's Report Abuse tools, and
the NCMEC CyberTipline for serious cases.

**What it deliberately is not:** a chat reader. Private Roblox chats are only
visible to Roblox's own moderators; any product claiming to read them is
either scraping the child's logged-in session (against Roblox's Terms of Use,
and grounds for App Store rejection) or lying. RobloxGuard works entirely from
Roblox's **public, unauthenticated APIs** and never asks for the child's
password.

**Known limits, stated plainly:** detection is pattern-matching over public
data, and pattern-matching is wrong in both directions. It will sometimes
flag something innocent (a false positive — a new friend's bio happens to
mention a Discord server for an unrelated reason), and it will sometimes miss
something real (a false negative — it cannot see private chats at all, so
grooming conducted entirely there produces no alert). No alert is a
determination, and no absence of alerts is a guarantee of safety. RobloxGuard
is **one tool a parent uses, not a standalone safety strategy** — it's meant
to sit alongside ongoing conversation with your child, Roblox's own parental
controls, and your own judgment, not replace any of them. The app's
onboarding requires parents to affirmatively acknowledge this before linking
an account, and every alert and report repeats it.

## How coverage works (the parent's-eye view)

**Nothing is installed on the child's device.** The app runs on the
*parent's* phone; the backend watches the child's *public* Roblox footprint,
which requires no access to their device, account, or password. That means
there's nothing for a child to find and delete, nothing that breaks on a new
device, and no credential handling to fail App Review.

Initiating coverage takes one minute:

1. Parent installs RobloxGuard on **their own** phone and completes the
   consent onboarding (attesting they are the parent/guardian).
2. Parent enters the child's **public Roblox username** — nothing else.
3. The backend takes a baseline snapshot immediately (surfacing any
   already-risky contacts, e.g. friends with off-platform handles in bios),
   then re-polls automatically every 15 minutes, around the clock.

## Daily threat search & automatic content updates

Two automations keep the whole product current without app releases:

1. **Daily threat intelligence** (`app/intel.py`): every 24 hours the backend
   reads configured sources (`data/intel_sources.json` — RSS feeds from
   child-safety orgs, platform-safety blogs), filters for Roblox-relevant
   findings, and turns them into a *proposed* threat-feed update using the
   Claude API (`claude-opus-4-8`, structured JSON output): newly abused chat
   apps with detection regexes, new grooming phrases, newly reported condo
   experiences, and new glossary terms. Safety valves: proposals are
   **additive only**, every regex must compile, all text is wording-checked
   (no person-labeling), hard per-run caps prevent a poisoned source from
   flooding the feed, and auto-apply is **off by default**
   (`RG_INTEL_AUTOAPPLY=1` to enable) — otherwise proposals land in
   `data/proposals/` for operator review. Without an Anthropic API key
   (`RG_ANTHROPIC_API_KEY`), a keyword fallback still collects and flags
   findings for manual review. Trigger manually with `POST /intel/run`;
   audit history at `GET /intel/runs`.
2. **Terms update automatically**: the versioned threat feed now carries
   content too — `glossary` entries (add or override any term definition)
   and `roblox_basics` entries. Since alert explainers and reports resolve
   terms through the active feed, publishing a feed update rewrites the
   plain-language layer on every install within the refresh TTL.

The app's Settings screen shows the active definitions version, where it
came from (built-in / remote / intel), and the last daily search.

## Staying ahead of new threats (adaptive design)

Three mechanisms keep detection current without app releases:

1. **Versioned threat feed** (`app/threat_feed.py`, seed in
   `data/threat_feed.json`): every pattern the detector matches — off-platform
   apps, grooming phrases, thresholds, condo-game watchlist — lives in a feed
   document. Set `RG_FEED_URL` and every install refreshes on a 6-hour TTL;
   publishing a new feed version deploys new threat intel fleet-wide within
   hours. Malformed or unreachable feeds never break detection: the last good
   feed stays active and the bundled seed is the floor.
2. **Obfuscation-resistant matching**: text is matched raw AND after folding
   leetspeak substitutions ("d1sc0rd" → "discord", "sn@p" → "snap"). A match
   that only appears after folding is called out in the alert as deliberate
   filter evasion — the evasion itself is evidence of intent.
3. **Parent feedback loop** (`POST /alerts/{id}/feedback`): "confirmed"
   switches that child to heightened monitoring (repeat behavior re-alerts
   after 2 hours instead of 12); three "dismissed" verdicts with no confirms
   mute that signal type for that child — except elevated alerts, which are
   never muted. The tuning rules are deliberately simple and documented, not
   a black box.

Robustness: Roblox API calls retry with exponential backoff on rate limits
and server errors (honoring `Retry-After`); per-friend profile failures
degrade to stubs instead of failing the snapshot; every child records
`last_poll_at`/`last_poll_status` so silent monitoring failures are visible
in the app rather than discovered too late.

## Architecture

```
roblox_guard/
├── backend/            FastAPI service (Python 3.11+)
│   ├── app/
│   │   ├── roblox_client.py   Async client for public Roblox web APIs
│   │   ├── signals.py         Risk-signal engine (pure functions, fully tested)
│   │   ├── monitor.py         Polling loop: snapshot → diff → alerts
│   │   ├── db.py              SQLite persistence (data-minimized)
│   │   ├── main.py            REST API consumed by the iOS app
│   │   └── resources.py       Reporting / escalation resources
│   ├── data/experience_watchlist.json   Curated watchlist (ships empty)
│   └── tests/                 40 tests: signals, monitor, API
└── ios/RobloxGuard/    SwiftUI parent app (iOS 17+, XcodeGen project)
```

### Signals the engine produces

| Signal | Severity | Trigger |
|---|---|---|
| `off_platform_handle` | elevated | A new friend's bio advertises Discord/Snapchat/Telegram/Kik/WhatsApp/Instagram handles or a phone number — the strongest observable grooming precursor (moving chat off-platform, away from Roblox's filters) |
| `established_account_contact` | watch | New friend's account is unusually old for a child's friend group |
| `large_network_contact` | watch | New friend has a friend count near Roblox's 1,000 cap (mass-friending pattern) |
| `rapid_friending` | watch | Child added many friends within a short window |
| `flagged_experience` | watch | Child observed playing an experience on the operator-curated watchlist |
| `quiet_hours_activity` | info | Account active during configured quiet hours |
| `new_friend` | info | Baseline notification with neutral context facts |

Every signal states **observable facts plus suggested parent actions**. A
wording guardrail (`signals.validate_wording`, enforced at emit time and in
tests) rejects any signal text that labels a person ("predator", "groomer",
etc.) — that's both a defamation guardrail and an App Review requirement.

### Evidence vault & incident reports

When a watch-level or elevated alert fires, the backend automatically
preserves what it saw:

- **Data snapshot** — machine-readable JSON of the exact observation.
- **Profile screenshot** — a headless-browser capture of the involved
  account's *public* profile page (bios get edited fast once someone feels
  watched). Uses Playwright; degrades gracefully if no browser is available.
- **Parent uploads** — screenshots the parent takes on the child's device
  (chats, profiles) imported through the app. The upload flow carries a
  non-skippable legal warning: sexual imagery of a minor must never be saved
  or uploaded, even as evidence — describe it to investigators instead.

Every item is timestamped and SHA-256 fingerprinted at capture time so
investigators can verify integrity. `GET /children/{id}/report` renders the
full incident report (HTML or Markdown): plain-language situation summary,
the danger patterns the observations match (from `app/education.py`), the
alert timeline, at-home behavioral signs to check, the evidence inventory
with hashes, and the reporting playbook (Roblox Report Abuse → NCMEC
CyberTipline → police). Unlinking a child erases evidence files along with
all database rows.

The underlying research — the full danger catalog and how to recognize a
targeted child — lives in [`docs/ROBLOX_DANGERS.md`](docs/ROBLOX_DANGERS.md)
and is served to the app at `GET /education`.

### Running the backend

```bash
cd backend
pip install -r requirements.txt
python -m pytest            # 40 tests
uvicorn app.main:app        # serves on :8000; monitor polls every 15 min
```

Key endpoints: `POST /children` (link, requires parental attestation),
`POST /children/{id}/refresh`, `GET /children/{id}/alerts`,
`POST /alerts/{id}/acknowledge`, `DELETE /children/{id}` (full erasure),
`GET /resources`.

### Building the iOS app

```bash
cd ios/RobloxGuard
xcodegen generate           # brew install xcodegen
open RobloxGuard.xcodeproj
```

Point `APIClient.baseURL` at your deployed backend (HTTPS in release).

## Pricing

Two auto-renewable subscription tiers via StoreKit 2 (`PurchaseManager.swift`,
`PaywallView.swift`), priced below the category leader (Bark: ~$5/mo or
$49/yr for one child, ~$14/mo or $99/yr for up to five) while keeping real
margin, since marginal cost per subscriber is near zero — Roblox's API is
free and the daily threat-intel run is a fixed cost shared across all users,
not billed per seat:

| Plan | Monthly | Annual | Covers |
|---|---|---|---|
| Single Child | $3.99 | $34 | 1 linked Roblox account, full alerts + evidence vault |
| Family | $8.99 | $69 | Up to 5 children, incident reports, priority protection updates |

There is no free tier — like Bark, the entry-level single-child plan is the
low-commitment option. The paywall (`PaywallView`) defaults the selection to
the annual plan on each tier, since annual billing is where subscription
monitoring apps retain past the "nothing's happened yet, do I still need
this" drop-off point. `DashboardView` routes to the paywall instead of the
link sheet when there's no active entitlement or the plan's child limit is
reached; `SettingsView` shows the active plan and links to Apple's native
manage-subscription sheet.

**Before this ships**, the four product IDs
(`com.mikeclaw.robloxguard.{single,family}.{monthly,annual}`) must be created
in App Store Connect matching `RobloxGuard.storekit` (which is a local test
configuration only, for Simulator testing — see `project.yml`), and receipt
validation / entitlement checks assumed here are client-side StoreKit 2
(`Transaction.currentEntitlements`), which is sufficient for gating local UI
but not for trusting the backend — if server-side features ever need to know
subscription state, verify entitlements server-side via App Store Server
Notifications rather than trusting the client.

## Smoke testing

Two layers, for two different questions.

**"Did I break anything?" — the pytest suite, offline, every commit:**

```bash
cd backend && python -m pytest -q     # 150 tests, ~20s, no network
```

This runs entirely against `FakeRobloxClient` (synthetic accounts only — see
`tests/test_e2e.py`), including a full parent journey (link → baseline →
threat → alert → evidence → report → feedback → erasure), hostile input, and
performance budgets. This is the CI gate; it never touches the real Roblox
API and never needs a live server.

**"Is the deployed instance actually working?" — `scripts/smoke_test.py`,
after every deploy:**

```bash
RG_SMOKE_URL=https://api.yourdomain.com RG_API_TOKEN=... \
    python backend/scripts/smoke_test.py
```

This hits a **running server** and the **real Roblox API**, exercising the
same critical path end-to-end: health + feed version, auth enforcement,
education content, linking an account, a live snapshot poll, alerts with
explainers, an evidence upload/hash/download round-trip, both incident-report
formats, intel status, and full erasure in a `finally` block so the smoke
run never leaves data behind — even on failure. It deliberately links
Roblox's own official `builderman` account rather than any child's account,
consistent with this project's policy of never monitoring a real minor
without their parent's consent, even for testing. Prints `PASS`/`FAIL` per
step and exits non-zero on any failure, so it's CI/CD-pipeline friendly as a
post-deploy gate.

**"Does it work on an actual iPhone?" — still outstanding, needs a Mac:**
Xcode build, run in Simulator/device, VoiceOver and Dynamic Type checks,
TestFlight beta. See *Production readiness* below and `docs/ROADMAP.md`.

## Bug log & reporting a bug

Two layers, so a bug is discoverable whether or not anyone tells you about it:

1. **Automatic error log.** Every `roblox_guard.*` logger writes to a rotating
   file (`app/logging_config.py`, capped at 5 × 5 MB, set `RG_LOG_DIR` to
   enable) so operational errors survive a process restart. Unhandled
   exceptions in any endpoint are additionally caught by a global FastAPI
   handler (`main.py`), logged with a full traceback, and never leak internals
   back to the app — the client just sees a generic 500.
2. **Customer-submitted reports.** The iOS app's Settings → Support → "Report
   a Bug" (`BugReportView.swift`) posts to `POST /support/bug-report` with a
   summary, optional details, and an optional reply-to email.

Both feed the same durable table — `bug_reports` in the backend database, the
actual "bug log" — queryable at `GET /support/bug-reports` regardless of
whether email is configured, so nothing is lost if SMTP isn't set up yet.
Set `RG_SMTP_HOST` (+ `RG_SMTP_USER`/`RG_SMTP_PASSWORD`/`RG_SMTP_PORT` as
needed) to also relay each customer report by email to `RG_SUPPORT_EMAIL`
(default `mvalasek@gmail.com`) via `app/mailer.py`. If the backend itself is
unreachable — often exactly when a parent most needs to reach someone — the
same screen has an independent "Email us directly" button that opens Mail
via a `mailto:` link straight to the support address, with no dependency on
the backend or network at all.

## Push notifications

Watch/elevated alerts push to every registered parent device the moment
`monitor.py` creates them — the whole point is hearing about a threat
without the app open. INFO-level baseline alerts don't push; they'd just be
noise.

**How it's wired:**
1. Settings → Notifications → "Enable Notifications" requests OS permission
   (`PushManager.swift`) and, once granted, UIKit hands the app a device
   token via `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`.
2. The token is sent to `POST /devices/register` and stored in the
   `device_tokens` table (`db.py`).
3. `monitor.py`'s `_push_alert` calls `app/push.py`'s `APNsService.send_to_all`
   for every new non-info alert, signing a fresh JWT (ES256, token-based
   auth — no certificates to renew) and posting to Apple's APNs HTTP/2 API.
   Tokens Apple reports as dead (410 Gone / BadDeviceToken) are pruned
   automatically.

There's no parent-account system yet (v0.1 uses one shared `RG_API_TOKEN` per
deployment), so every registered device receives every push for that
deployment — consistent with the single-family-per-backend model everywhere
else in this app.

**Getting a real APNs key**, in App Store Connect → Users and Access → Keys
(previously under Certificates): create a key with the "Apple Push
Notifications service (APNs)" capability, download the `.p8` file once (it
can't be re-downloaded), and note the Key ID and your Team ID. Then set:

```bash
RG_APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"   # or RG_APNS_KEY_PATH=/path/to/key.p8
RG_APNS_KEY_ID=XXXXXXXXXX
RG_APNS_TEAM_ID=YYYYYYYYYY
RG_APNS_BUNDLE_ID=com.mikeclaw.robloxguard      # default already matches
RG_APNS_SANDBOX=1                                # unset/0 once shipping to the App Store
```

Unconfigured is a deliberate no-op (same pattern as `RG_SMTP_HOST` for the
bug-log emailer) — the rest of the app works fine without it, `GET
/notifications/status` reports `configured: false`, and nothing crashes.

### Testing it

Waiting for `monitor.py` to organically detect a real risky signal is slow
and hard to reproduce on demand, so there's a manual trigger for exactly
this:

1. **Offline, no Apple account needed:** `pytest tests/test_push.py` — 22
   tests covering JWT signing, delivery, dead-token pruning, and that the
   monitor hook fires for watch/elevated but stays silent for INFO alerts,
   all against a mocked APNs.
2. **Backend sanity without a device:** `POST /devices/register` a fake
   token, then `GET /notifications/status` to confirm it's stored. With a
   real APNs key configured, `scripts/smoke_test.py` also calls
   `POST /notifications/test` and checks Apple's API was *reachable*
   (JWT + HTTP/2 handshake worked) — it can't check real delivery since the
   smoke test's token isn't a real device.
3. **In the iOS Simulator** — two different things get tested here, and
   they're not the same check:
   - *Does our app + backend plumbing work?* Run the app in Simulator
     (`Cmd+R` after `xcodegen generate` and opening `RobloxGuard.xcodeproj`),
     go to Settings → Notifications → Enable Notifications, grant the
     permission prompt (Simulator supports this natively). The app will get
     a *placeholder* device token from `didRegisterForRemoteNotificationsWithDeviceToken`
     and register it with the backend — confirm via `GET /notifications/status`
     that `registered_devices` went up by one. This proves the entire
     client-side chain (permission → token → `APIClient.registerDevice` →
     `POST /devices/register`) works. Tapping "Send test notification"
     afterward will reach the backend and attempt real APNs delivery, but
     Apple will almost certainly reject a Simulator-origin token — that's
     expected, not a bug; it's still proof the backend-to-Apple leg (JWT
     signing, HTTP/2 handshake) works, same as `smoke_test.py`'s check.
   - *Does the notification actually look right when it arrives?* Simulator
     can't receive genuine remote pushes from Apple, so use Apple's own
     local-injection tool instead, which bypasses APNs entirely and just
     tests rendering:
     ```bash
     xcrun simctl push booted com.mikeclaw.robloxguard ios/RobloxGuard/test-push.apns
     ```
     (`booted` targets whichever Simulator is currently running; swap in a
     specific device UDID from `xcrun simctl list` if you have more than
     one booted.) That file already matches the real payload shape
     `app/push.py` sends. You should see the banner, hear the sound, and
     the app's badge should update — if it doesn't, the gap is in the
     client (entitlement, permission, or notification delegate), not the
     backend. Note there's currently no notification-tap handler, so
     tapping it just opens to whatever screen the app was last on rather
     than deep-linking to the specific alert — that's a real gap, not
     tested here, and would be a good next addition.
4. **The real test, on a physical iPhone** (the only way to confirm actual
   end-to-end delivery through Apple's servers): same Settings flow as
   above, but on real hardware with a debug/dev provisioning profile. Tap
   "Send test notification" and you should get a real push within a few
   seconds — that's the chain fully proven, permission through delivery.
5. Only once step 4 works should you trust that a *real* alert (e.g. link a
   test child whose friend's bio contains a Discord handle) will actually
   reach the device — that exercises `monitor.py`'s real trigger path
   instead of the manual one.

## Production readiness

What's verified here and what still needs real-device work before launch:

**Verified in CI (150 tests):** full parent journey end-to-end (link →
baseline → threat → alert → evidence → report → feedback → erasure), hostile
input (unicode, null bytes, script injection — HTML reports escape it),
oversized uploads rejected, unknown-ID and validation paths, API auth
(bearer token, constant-time compare, /health open for probes), bug log +
report submission (DB persistence, mailer no-op/success/failure paths), push
notification delivery (JWT signing, dead-token pruning, the monitor hook that
fires per non-info alert — mocked APNs, since real delivery needs a live
Apple key), performance
budgets (250-friend snapshot < 5s through the whole pipeline, no-change
re-poll < 2s), rapid-friending baseline bug fixed (was firing a false alert
on every second poll after linking — caught by the perf test).

**Requires a Mac/device before launch (cannot run on this CI host):** Xcode
build + XCUITest flows, VoiceOver walkthrough, Dynamic Type at largest
sizes, live roblox.com API smoke test, TestFlight beta. Deployment needs:
HTTPS termination, `RG_API_TOKEN` set, Postgres for multi-instance,
APNs for alert pushes (see docs/ROADMAP.md — this is the v0.2 blocker).

### Getting onto App Store Connect via Xcode Cloud

This part can't be done from a headless environment — it requires Xcode's
GUI and your own Apple Developer account. What's already prepped in the
repo, and what's left for you on a Mac:

**Prepped here:**
- `project.yml` — XcodeGen project definition (bundle ID
  `com.mikeclaw.robloxguard`, iOS 17+ target).
- `ci_scripts/ci_post_clone.sh` — Xcode Cloud hook that installs XcodeGen and
  runs `xcodegen generate` on every CI build, so the built project can never
  drift from `project.yml`.

**Still needed, on a Mac, roughly in order:**
1. Enroll in the Apple Developer Program if you haven't (paid, tied to your
   Apple ID — this is the account/billing step only you can do).
2. `cd roblox_guard/ios/RobloxGuard && xcodegen generate`, then commit the
   resulting `RobloxGuard.xcodeproj` — Xcode Cloud's setup wizard needs a
   project file already in the repo to detect and select; after this one
   bootstrap commit, `ci_post_clone.sh` keeps it regenerated automatically.
3. Open the project in Xcode, register the bundle ID
   (`com.mikeclaw.robloxguard`) and create the app record in App Store
   Connect (or let Xcode Cloud's setup flow create it for you).
4. Product → Xcode Cloud → Create Workflow, authorize access to this GitHub
   repo, select the branch to build from, and let it run its first build —
   this is the first time the app has ever actually compiled, so expect to
   fix real build errors (nothing here has been verified to compile).
5. App icon is done — `Sources/Assets.xcassets/AppIcon.appiconset`, an
   original shield-and-block mark (not derived from Roblox's branding; see
   `ios/RobloxGuard/Design/generate_app_icon.py` to regenerate/edit it).
6. Create the four subscription products in App Store Connect matching
   `RobloxGuard.storekit` (see "Pricing" above) before StoreKit works for
   real users — `RobloxGuard.storekit` only covers local Simulator testing.
7. TestFlight beta once a build passes Xcode Cloud, before public submission.

## App Store compliance design

| Guideline | How RobloxGuard complies |
|---|---|
| **1.3 Kids Category** | Not a Kids Category app. The app is used by the *parent*; the child never opens it. |
| **5.1.1 / 5.1.4 Privacy & kids' data** | Explicit parental-consent onboarding (attestation stored with who/when); data minimization (username + derived alerts only, no chat, no mirrored social graph); unlink = immediate full deletion; no third-party ads or analytics SDKs. |
| **5.2.2 Third-party services** | Only public, unauthenticated Roblox endpoints; no credential collection (there is no password field anywhere in the app); polite request throttling. |
| **5.4 / 5.5 VPN & MDM** | Uses neither. If device-level controls are added later, they must use Apple's Screen Time API (FamilyControls / DeviceActivity), not VPN or MDM profiles. |
| **1.1 Objectionable content** | Signals are factual and label-free (test-enforced); escalation is always to Roblox moderation, NCMEC, or police — never in-app confrontation or naming-and-shaming. |
| **3.1.1 Payments** | Any future subscription goes through In-App Purchase. |

## Legal notes (not legal advice — review with counsel before shipping)

- **COPPA / GDPR-K**: the parent is the account holder, but the app still
  processes data *about* a minor. The consent attestation, data-minimized
  storage, and one-tap full deletion are designed for this; production needs a
  published privacy policy and accurate App Privacy labels.
- **CSAM**: the app never ingests or stores imagery. If a parent encounters
  suspected CSAM, the app's guidance routes them to the CyberTipline —
  it must never be uploaded, downloaded, or attached anywhere in the product.
- **Watchlist**: `experience_watchlist.json` ships empty. Entries are
  editorial judgments the operator must own, keep current, and word factually.
