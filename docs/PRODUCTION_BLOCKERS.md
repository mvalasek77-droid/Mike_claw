# Production Blockers

What stands between CodeGenie and being shippable software vs being a polished demo.
Last audited at the `claude/finish-line` branch, after the 0.2.0 polish pass.

**Status legend**:
- `wired` — code exists and is exercised by tests or a build path.
- `stubbed` — UI references it but no implementation actually runs.
- `external` — needs decisions / infrastructure outside this repo.

---

## 1. iOS app marketing promises

| Surface | Promise | Status | What's actually missing |
|---|---|---|---|
| OnboardingSlide step 6 | "Icon forged with ChatGPT" | **wired** (v0.2.1) | `backend/genie_swarm/icon_gen.py` calls OpenAI's `gpt-image-1` model, drops the PNG into `Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Route: `POST /api/coding/swarm/<job>/icon/generate`. iOS surface: `SwarmClient.generateAppIcon(...)`. Needs `OPENAI_API_KEY` in the backend env. |
| OnboardingSlide step 6 / ASC step 3 | "1024×1024 PNG, no alpha, no rounded corners. CodeGenie strips alpha automatically" | **wired** (v0.2.1) | `_strip_alpha_if_possible()` flattens transparency onto white when Pillow is installed; gracefully passes raw bytes through with a logged warning when not. Pillow added to `requirements.txt`. |
| ASC step 4 | "Auto-generate screenshots" | **stubbed** | `screenshot_diff.py` exists for *comparing* screenshots; nothing actually captures them. Orchestrator prompts mention `simctl io booted screenshot` but no Python code drives it. |
| OnboardingSlide step 5 | "iterates until the UI is correct, the data flows, and the build is green" | **partial** | The 8-agent orchestrator is real. Whether it actually produces a green build for arbitrary user prompts has never been verified end-to-end on a real Apple Dev account. |

## 2. StoreKit + payments

| Item | Status | Note |
|---|---|---|
| `BillingPlan` enum + `BillingStore` reads | **wired** | iOS code is complete. |
| Product IDs `com.codegenie.pro.monthly`, `com.codegenie.studio.monthly` | **external** | Not yet configured in App Store Connect. Until they are, `BillingStore.products` is always empty and the Pro/Studio pills can't be purchased. |
| Prices, durations, screenshots, descriptions for both products | **external** | Same — needs ASC entry. |
| Receipt validation / restore | **stubbed** | iOS code reads `Transaction.currentEntitlements` correctly. No server-side receipt validation. Acceptable for IAP; tighten if revenue grows. |

## 3. Backend infrastructure

| Item | Status | Note |
|---|---|---|
| FastAPI app (`backend/genie_swarm/api.py`) | **wired** | 141 tests passing. Runs locally. |
| `api.codegenie.app` deployment | **external** | Referenced in `Credentials.swift` as the default backend URL. No deploy config (Dockerfile, fly.toml, render.yaml, etc.) exists in the repo. Until something is hosting at that URL, hosted plan + bug-report submission both fail in production. |
| Backend secrets management | **external** | The backend needs Anthropic + OpenAI API keys, ASC keys for upload-on-behalf, etc. No `.env.example` or secrets doc exists. |
| Logging / observability | **stubbed** | Backend prints; no structured logging, no metrics export. |

## 4. CodeGenie domain & supporting properties

| Item | Status | Note |
|---|---|---|
| `codegenie.app` domain | **external** | Hard-coded in multiple iOS files: `TermsAndPrivacyView` (terms + privacy URLs), `PairMacView` (companion download), `Credentials` (default backend URL). Until owned + DNS-configured, every Link/Safari path 404s. |
| `codegenie.app/terms` page | **external** | Referenced by Terms gate. Must exist before app can pass App Review. |
| `codegenie.app/privacy` page | **external** | Same. |
| `codegenie.app/companion` download page | **external** | PairMacView's primary CTA goes here. |

## 5. Mac Companion app

| Item | Status | Note |
|---|---|---|
| Mac Companion app source | **missing from this repo** | The iOS app expects a Bonjour service `_codegenie-companion._tcp` and HTTP endpoints on the paired Mac for build / Safari driving. The source for that companion is not in this repo. |
| Distribution (signed, notarized) | **external** | Until the companion is built, signed, and downloadable from `codegenie.app/companion`, pairing fails. |

## 6. Apple-required iOS pieces

| Item | Status | Note |
|---|---|---|
| `Info.plist` usage descriptions | **wired** | NSCameraUsageDescription, NSLocalNetworkUsageDescription, NSPhotoLibraryAddUsageDescription, NSBonjourServices all present. |
| `PrivacyInfo.xcprivacy` | **missing** | Required by Apple for all new app submissions since May 2024. Must declare Required Reasons API usage and any third-party SDKs. |
| App icon (CodeGenie's own) | **placeholder** | `Assets.xcassets/AppIcon.appiconset/README.md` excluded from build per `project.yml`, suggesting a placeholder icon set. Verify before ASC submission. |
| App Store metadata for CodeGenie | **missing** | Description, keywords, screenshots, age rating, privacy answers — none drafted in this repo. |

## 7. QA matrix

| Item | Status | Note |
|---|---|---|
| `docs/qa/PAGE_PROCESS_MATRIX.md` | **baseline** | 99 rows committed. **98 of them** still `not tested`. The `AGENT_QA_PROTOCOL.md` rule "no green check without evidence" means by our own protocol every release is currently blocked. |
| Light/dark mode screenshots | **missing** |
| AX5 Dynamic Type pass | **missing** |
| Reduce Motion pass | **missing** |
| VoiceOver runtime pass | **code-level only** | Headers, hints, contain-children adds in 0.2.0. Never tested on real hardware. |
| iOS XCTest target | **missing** | The matrix has `Evidence` columns waiting for `test:<name>` pointers; no test target exists. |

## 8. End-to-end verification

**No app has ever been built and shipped end-to-end with CodeGenie.** This is the headline blocker. Until one human runs Describe → Build → Submit → TestFlight successfully with a real Apple Developer account and a real generated `.ipa`, every "it should work" claim above is theoretical.

A simple v0.2.0 dogfood pass: build a TideTimes app, submit it to your own TestFlight via CodeGenie, watch what breaks, fix that, repeat.

---

## Recommended order of operations

1. Stand up `api.codegenie.app` somewhere (Fly, Render, Cloudflare Tunnels) — unblocks Hosted plan + bug reports
2. Buy / point `codegenie.app` and serve a terms + privacy page — unblocks App Review
3. Configure the two StoreKit products in ASC — unblocks Pro/Studio purchase
4. Ship `PrivacyInfo.xcprivacy` — unblocks App Review
5. Dogfood once: ship TideTimes via CodeGenie to your own TestFlight
6. Mac Companion app source + signed build — unblocks the pair-your-Mac flow
7. ~~Implement icon generation (call OpenAI's image API)~~ — done in v0.2.1.
8. Implement simctl screenshot capture or remove the promise from ASC step 4
