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
