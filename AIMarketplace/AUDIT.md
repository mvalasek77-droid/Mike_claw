# Platform Audit — AI Marketplace vs Amazon/KDP, Netflix, Google Play, Apple

**Date:** 2026-05-25  ·  **Scope:** the iOS app on branch `claude/ai-marketplace-ios-app-iUYui`.

## Honest headline

AI Marketplace is, today, a **client-only iOS app**: a rich, demo-complete
**frontend** with **local, on-device persistence** and **no server backend**.
It convincingly demonstrates the *product* (a KDP × Netflix marketplace for
AI‑made media with an AI quality gate), but the systems that make Amazon /
Netflix / Google Play / Apple actually work at scale — accounts, payments,
content delivery, search/recommendation services, moderation, DRM — are either
**simulated on-device** or **not present**. This document maps every system,
front and back, and is deliberately blunt about what is real vs. demo vs.
missing. Nothing here fakes a backend.

Legend: ✅ present · 🟡 partial / simulated · ❌ missing

---

## 1. Storefront & discovery (frontend)

| System | Amazon | Netflix | Google Play | Apple | AI Marketplace | Notes |
|---|:--:|:--:|:--:|:--:|:--:|---|
| Cinematic home / featured hero | ✅ | ✅ | ✅ | ✅ | ✅ | `BrowseHomeView` + `HeroBanner` |
| Curated rows | ✅ | ✅ | ✅ | ✅ | ✅ | Top 10, Trending, Just Published, per-type |
| Charts / bestsellers | ✅ | ✅ | ✅ | ✅ | ✅ | `ChartsView`, ranked Top 10 |
| **Search** | ✅ | ✅ | ✅ | ✅ | ✅ | **Added** `SearchView` (title/creator/genre/synopsis/AI tool) |
| Browse by genre/category | ✅ | ✅ | ✅ | ✅ | 🟡 | Type pills + genre chips in search; no dedicated genre browse screen |
| Personalized recommendations | ✅ | ✅ | ✅ | ✅ | ❌ | No "because you watched/bought"; needs a reco service |
| Product/title detail page | ✅ | ✅ | ✅ | ✅ | ✅ | `MediaDetailView` |
| Ratings & reviews | ✅ | 🟡 | ✅ | ✅ | ❌ | No user ratings/reviews model or UI |
| Wishlist / My List | ✅ | ✅ | ✅ | ✅ | ✅ | Watchlist in store |
| Samples / previews / trailers | ✅ | ✅ | ✅ | ✅ | 🟡 | Players exist; no explicit free-sample gating |
| Creator/AI spotlight pages | 🟡 | 🟡 | 🟡 | 🟡 | ✅ | `AISpotlightView` — unique to this product |
| Editor-generated catalogue fill | — | 🟡 | — | — | ✅ | `ContentFoundry` Originals fill thin categories — unique |
| Localization / i18n | ✅ | ✅ | ✅ | ✅ | ❌ | Single locale, hard-coded strings |

## 2. Playback & consumption

| System | Reference | AI Marketplace | Notes |
|---|---|:--:|---|
| Video player | Netflix | ✅ | AVKit `VideoPlayer` |
| Audio player | Apple Music | ✅ | `AVPlayer` + custom transport |
| Reader | Kindle | ✅ | Paginated reader, font sizing |
| Resume / playback position | all | ❌ | No saved position, no cross-device |
| Offline downloads | all | ❌ | No download manager |
| AirPlay / casting | Netflix/Apple | 🟡 | AVKit exposes AirPlay for video; not surfaced/tested |
| Adaptive streaming (HLS/DASH) | all | ❌ | Local/bundled files only; no streaming backend |
| **DRM / content protection** | all | ❌ | No FairPlay/Widevine; **blocker for licensed content** |

## 3. Commerce & payments

| System | Reference | AI Marketplace | Notes |
|---|---|:--:|---|
| Buy digital good | all | 🟡 | Wallet credit (StoreKit-funded) → title unlock |
| **StoreKit In-App Purchase** | Apple (required) | ✅ | **Fixed** — `StoreKitService` consumable credit packs; Apple Pay removed |
| Cart / multi-item checkout | Amazon/Google | 🟡 | Single-item buy only |
| Subscriptions | Netflix | ❌ | No subscription tier/billing |
| Order history / receipts | all | 🟡 | Library = entitlements; no receipts/invoices |
| Refunds / chargebacks | all | ❌ | None |
| Tax / VAT / regional pricing | all | ❌ | Flat USD, no tax engine |
| Promo codes / gifting | all | ❌ | None |
| Server-side receipt validation | all | ❌ | Client verifies tx; no server validation yet |

## 4. Creator / seller systems (KDP, YouTube, App Store Connect)

| System | Reference | AI Marketplace | Notes |
|---|---|:--:|---|
| Registration / onboarding | KDP/ASC | ✅ | `RegisterView` (local only) |
| Publishing wizard | KDP | ✅ | Format→details→disclosure→content→cover→pricing→review |
| Cover/art upload | KDP | ✅ | PhotosPicker cover step |
| Content quality review | ASC review | ✅ | **AI Editor** (85% bar) — unique |
| Autonomous publishing | — | ✅ | **AI Autopilot** — unique |
| Analytics dashboard | ASC/KDP | ✅ | `CreatorDashboardView`: units, proceeds, trend |
| Royalties / payouts | KDP | 🟡 | **Partner Program added**: withdrawable USD balance, payout connect, cash-out, NRN→USD; real disbursement/KYC/tax still backend (`/payouts`) |
| Creator/AI acquisition & incentives | KDP/YouTube | 🟡 | **Partner Program + incentive engine** (invite AIs → ship media → earn real USD + NRN signing/quality/bounty bonuses, tiers, leaderboard); strategy in `PARTNERS.md` |
| Catalog management (edit/unpublish/versioning) | all | ❌ | Publish only; cannot edit, unpublish, or re-version |
| Human moderation / abuse reports | all | ❌ | Only the on-device AI heuristic; no report flow |
| Rights / AI disclosure | — | ✅ | Mandatory AI disclosure — unique |

## 5. Identity, account & security

| System | Reference | AI Marketplace | Notes |
|---|---|:--:|---|
| Real authentication (Sign in with Apple/OAuth) | all | 🟡 | **Sign in with Apple added** (client); server token exchange specced in `backend/openapi.yaml` |
| Account management (change/delete) | all | 🟡 | **Account deletion + sign out added**; profile editing still TODO |
| Multi-device sync | all | ❌ | No iCloud/account sync |
| Encryption at rest | all | ✅ | AES-GCM (CryptoKit) + Keychain |
| Privacy manifest / policy / terms | all | ✅ | `PrivacyInfo.xcprivacy` + in-app docs |
| Parental controls / ratings enforcement | all | 🟡 | Maturity field exists; no PIN/enforcement |
| Fraud, rate limiting, bot defense | all | ❌ | No backend |

## 6. Backend & infrastructure (the big gap)

| System | Reference | AI Marketplace | Notes |
|---|---|:--:|---|
| API / application services | all | 🟡 | No server yet, but the full contract is specced in `backend/openapi.yaml` |
| Database | all | 🟡 | Local encrypted file (`EncryptedArchive`); no server DB |
| Object storage + CDN for media | all | ❌ | Bundled/local files; no upload pipeline or CDN |
| Search index | all | 🟡 | In-memory client filter; no Elasticsearch/Algolia-class service |
| Recommendation engine | all | ❌ | None |
| Catalog / inventory service | all | 🟡 | Seed data + user-published, all local |
| Payments backend / processor | all | ❌ | No Stripe/Apple server validation |
| Auth / identity service | all | ❌ | None |
| Push notifications | all | ❌ | None |
| Analytics / telemetry | all | ❌ | None |
| Content moderation pipeline | all | 🟡 | On-device AI Editor heuristic only |
| Observability (logs/metrics/traces) | all | ❌ | None |
| DRM / license server | all | ❌ | None |

## 7. App Store compliance flags (must-fix before submission)

1. ✅ **RESOLVED — Digital goods now use StoreKit IAP** (Guideline 3.1.1).
   Apple Pay (which is for *physical* goods) has been removed. Real money now
   enters only through **StoreKit 2 consumable credit packs** (`StoreKitService`
   + `Products.storekit`); titles unlock by spending wallet credit. Remaining
   work: server-side receipt validation, and confirm the 70/30 vs. 85/15
   small-business cut against the 85% creator share in App Store Connect.
2. ✅ **RESOLVED — Account deletion** added (`MarketplaceStore.deleteAccount()`,
   Profile → Account → Delete account), required once accounts exist
   (Guideline 5.1.1(v)). Sign in with Apple is also wired (Guideline 4.8).
3. **UGC controls** (Guideline 1.2): need report/block/abuse flow + human
   moderation, not just the AI Editor.
4. Hosted **privacy policy + terms URLs** for the listing (in-app text exists).

---

## 8. Prioritized path to parity

**P0 — make it a real product (backend foundation)** — contract in `backend/openapi.yaml`
- Implement the API + Postgres against the OpenAPI spec; move catalog, accounts,
  entitlements, drafts server-side.
- Auth: Sign in with Apple is wired client-side ✅; add the server token
  exchange (`POST /auth/apple`) + sessions. Account deletion done ✅.
- Media pipeline: signed uploads → object storage (S3/GCS) → CDN; transcode to HLS.
- **StoreKit 2 IAP** done ✅; add **server receipt validation**
  (`POST /commerce/validate-receipt`).

**P1 — discovery & trust parity**
- Search service (Algolia/Elasticsearch) + recommendations.
- Ratings & reviews (model, moderation, anti-fraud).
- DRM (FairPlay) for licensed playback; offline downloads with license lease.
- Push notifications; resume/position sync.

**P2 — creator & marketplace depth**
- Real payouts (Stripe Connect/Apple), KYC, tax forms (1099/DAC7), statements.
- Catalog management: edit, version, unpublish, scheduling.
- Human moderation console + appeals; abuse reporting.

**P3 — scale & internationalization**
- Localization, multi-currency, regional pricing & tax.
- Subscriptions/bundles, gifting, promo codes.
- Observability, analytics, A/B framework.

---

## 9. Where AI Marketplace already leads

The AI-native pieces have **no direct equivalent** on the incumbents and are the
product's moat: **mandatory AI disclosure**, the **AI Editor** commercial-quality
gate (85% bar, explainable rubric), **AI Autopilot** autonomous publishing,
**AI Spotlight** per-model portfolios, the **AI Editor's content foundry**
(which produces its own high-quality Originals to keep the catalogue full when
creators haven't uploaded), and **Neuron (NRN)** — an on-chain AI-to-AI
settlement currency with a live ledger and block explorer that none of the
incumbents have. The frontend that showcases these is genuinely strong; the
work ahead is the backend and commerce plumbing the incumbents spent a decade
building.

> Note on NRN: the blockchain is a real, self-contained hash-linked ledger with
> proof-of-work, but it runs **on-device** and is **not** a public, distributed
> chain. Making it a true cryptocurrency would require a networked consensus
> layer, wallets/keys per agent, and (for real value) regulatory work — tracked
> as future scope, not claimed as shipped.
