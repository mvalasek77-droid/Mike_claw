# App Store metadata & submission checklist

Reference for the App Store Connect listing and what the app requires to pass
review. Keep in sync with `project.yml`, `Info.plist`, the entitlements and the
privacy manifest.

## Listing
- **Name:** AI Marketplace
- **Subtitle:** AI novels, music & film
- **Category:** Entertainment (`public.app-category.entertainment`)
- **Bundle ID:** `com.aimarketplace.app`
- **Age rating:** 12+ (user-generated content; per-title maturity ratings)
- **Promotional text:** Discover AI-made stories, music and film — vetted to
  commercial quality, then stream or read them in dedicated players.
- **Keywords:** ai, marketplace, novels, music, movies, streaming, publishing,
  creators, generative, store

### Description (draft)
AI Marketplace is where machine-made media goes commercial. Creators register
their AI-generated novels, albums and films, disclose exactly which AI made
them, and submit to the AI Editor — which only passes work that clears an 85%
commercial-quality bar. Accepted titles go live in a cinematic store with a
Top 10, a Trending list, and dedicated players for reading, listening and
watching. Buy what you love; creators keep 85% of every sale.

## Capabilities / entitlements
- **Apple Pay (In-App Payments):** `merchant.com.aimarketplace.app`
  (replace with your real merchant ID; register it in the Apple Developer
  portal and create a Merchant ID + payment processing certificate).
- No HealthKit / location / contacts / tracking.

## Privacy (App Privacy "nutrition label")
Declared in `Resources/PrivacyInfo.xcprivacy`:
- **Data collected (linked, not used for tracking):** email, name, purchase
  history — all for App Functionality only.
- **Tracking:** none (`NSPrivacyTracking = false`).
- **Required-reason APIs:** UserDefaults (CA92.1), File timestamp (C617.1).

## Info.plist highlights
- `NSPhotoLibraryUsageDescription` — cover-art selection during publishing.
- `LSApplicationCategoryType` — entertainment.
- `ITSAppUsesNonExemptEncryption = false` — uses only Apple-provided standard
  encryption (CryptoKit AES-GCM) to protect the app's own on-device data, which
  qualifies for the export-compliance exemption.
- `UIUserInterfaceStyle = Dark`.

## Review notes (guideline mapping)
- **3.1.1 (IAP):** purchases of digital content use Apple Pay / in-app
  commerce; no external purchase links.
- **5.1.1 (Privacy):** privacy policy + terms are in-app (Profile → Privacy &
  legal) and must also be hosted at a public URL for the listing.
- **1.2 / UGC:** AI disclosure is mandatory per title; report/removal flow and
  maturity ratings are present; expand moderation before scale.
- **2.3 (Accurate metadata):** screenshots should show the store, a title page,
  the publishing flow, and the AI Editor verdict.

## Pre-submit checklist
- [ ] Replace placeholder merchant ID and wire real payment processing.
- [ ] Host privacy policy + terms at public URLs; add to the listing.
- [ ] Provide a 1024×1024 marketing icon and device screenshots.
- [ ] Set the real `DEVELOPMENT_TEAM` in `project.yml`.
- [ ] Run on device; verify Apple Pay sheet with a sandbox account.
