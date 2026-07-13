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

## Smoke testing

Two layers, for two different questions.

**"Did I break anything?" — the pytest suite, offline, every commit:**

```bash
cd backend && python -m pytest -q     # 119 tests, ~20s, no network
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

## Production readiness

What's verified here and what still needs real-device work before launch:

**Verified in CI (119 tests):** full parent journey end-to-end (link →
baseline → threat → alert → evidence → report → feedback → erasure), hostile
input (unicode, null bytes, script injection — HTML reports escape it),
oversized uploads rejected, unknown-ID and validation paths, API auth
(bearer token, constant-time compare, /health open for probes), performance
budgets (250-friend snapshot < 5s through the whole pipeline, no-change
re-poll < 2s), rapid-friending baseline bug fixed (was firing a false alert
on every second poll after linking — caught by the perf test).

**Requires a Mac/device before launch (cannot run on this CI host):** Xcode
build + XCUITest flows, VoiceOver walkthrough, Dynamic Type at largest
sizes, live roblox.com API smoke test, TestFlight beta. Deployment needs:
HTTPS termination, `RG_API_TOKEN` set, Postgres for multi-instance,
APNs for alert pushes (see docs/ROADMAP.md — this is the v0.2 blocker).

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
