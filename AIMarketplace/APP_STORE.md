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
watching. Buy what you love; after Apple's App Store commission, creators keep
85% of the remaining proceeds.

## Capabilities / entitlements
- **Sign in with Apple:** entitlement `com.apple.developer.applesignin = [Default]`
  (in `AIMarketplace.entitlements`). Requires a paid Apple Developer membership.
  In Xcode: select your **Team**, use a **bundle ID unique to your account**
  (the default `com.aimarketplace.app` is likely not registered to you — change
  it), and with automatic signing Xcode registers the App ID + capability. If it
  still complains, in Signing & Capabilities remove and re-add "+ Sign in with
  Apple" to force registration.
- **In-App Purchase (StoreKit 2):** consumable wallet-credit products. Define
  these in App Store Connect mirroring `Products.storekit`:
  `com.aimarketplace.credits.5/.10/.25/.50`. No special entitlements file key is
  required for IAP. (Apple Pay has been removed — it is not permitted for
  digital goods under Guideline 3.1.1.)
- For local testing: set **Edit Scheme → Run → Options → StoreKit
  Configuration** to `Products.storekit`.
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
- **3.1.1 (IAP):** digital purchases use StoreKit IAP (consumable credit packs);
  no Apple Pay for digital goods and no external purchase links.
- **5.1.1 (Privacy):** privacy policy + terms are in-app (Profile → Privacy &
  legal) and must also be hosted at a public URL for the listing.
- **5.1.1(v) (Account deletion):** in-app account deletion is implemented
  (Profile → Account → Delete account).
- **4.8 (Sign in with Apple):** offered as a login option in registration.
- **1.2 / UGC:** AI disclosure is mandatory per title; report/removal flow and
  maturity ratings are present; expand moderation before scale.
- **2.3 (Accurate metadata):** screenshots should show the store, a title page,
  the publishing flow, and the AI Editor verdict.

## Pre-submit checklist
- [ ] Create the credit-pack IAP products in App Store Connect (match `Products.storekit`).
- [ ] Add server-side receipt validation for the credit purchases.
- [ ] Host privacy policy + terms at public URLs; add to the listing.
- [ ] Provide a 1024×1024 marketing icon and device screenshots.
- [ ] Set the real `DEVELOPMENT_TEAM` in `project.yml`.
- [ ] Run on device with a sandbox account; verify a credit purchase + a title unlock.
