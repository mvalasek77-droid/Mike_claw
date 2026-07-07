# ChadDrop App Store Connect Answers

Use this as the copy/paste sheet when App Store Connect asks for app information.

## New App Record

- Platform: iOS
- Name: ChadDrop
- Primary language: English (U.S.)
- Bundle ID: `com.valasek.chaddrop`
- SKU: `CHADDROP-IOS-1`
- User access: Full Access

If the name ChadDrop is unavailable, keep the installed app display name as ChadDrop and choose a public App Store name that Apple accepts.

## App Icon

CodeGenie can create and validate the app icon:

```sh
TruthTranslator/Scripts/create_app_icon.sh
```

Expected result:
- Width: 1024
- Height: 1024
- Alpha: no

After creating a new icon, rebuild or archive the app so Apple receives it inside the uploaded build.

## Screenshots

CodeGenie can capture simulator screenshots:

```sh
TruthTranslator/Scripts/capture_appstore_screenshots.sh
```

Use screenshots from:

```text
TruthTranslator/AppStore/Screenshots/Public
```

Do not upload screenshots from `InternalWalkthrough`. Those are only for guiding the release process and can confuse review because they mention release tooling instead of the user-facing app.

Apple accepts one to ten screenshots per device/language in PNG, JPG, or JPEG format. Use the highest-resolution iPhone screenshots first; App Store Connect can scale them for other sizes when appropriate.

The capture script removes the simulator status bar band from public and IAP review screenshots. In App Store Connect, open "View All Sizes in Media Manager" and replace every old screenshot size that still shows a non-iOS or stale status bar.

For subscription review information, use:

```text
TruthTranslator/AppStore/Screenshots/IAPReview/chaddrop-pro-paywall.png
```

This screenshot is for each subscription product's App Review Screenshot field, not for the public App Store screenshot gallery.

## App Information

- Category: Lifestyle
- Content Rights: No third-party copyrighted content is required by the app.
- Age Rating: Answer Apple's questionnaire honestly. Because the app has mild crude humor and relationship content, expect a teen-friendly rating rather than a kids rating.

## Version Information

- Version: `1.0.0`
- Promotional Text: Paste a message, pick the tone, and get a psychology-informed translation plus replies you can send without losing your standards.
- Subtitle: Decode texts with humor.
- Keywords: `text,dating,relationships,advice,humor,chat,replies,messages`
- Support URL: `https://mvalasek77-droid.github.io/chaddrop-support/support.html`
- Privacy Policy URL: `https://mvalasek77-droid.github.io/chaddrop-support/privacy.html`
- Terms of Use (EULA): `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`

## Description

ChadDrop turns vague, confusing, or suspicious texts into plain-language reads with humor, pattern spotting, and suggested replies.

Designed for women decoding dating, friend, and work messages, it looks for effort, ambiguity, timing, follow-through, and whether the words include an actual plan.

Features:
- Paste any text and decode it in seconds.
- Choose Gentle, Group Chat, or Crude-ish tone.
- See the likely translation, psychology read, receipts, flags, and truth score.
- Copy suggested replies.
- Start with a few free decodes, then unlock unlimited decodes with ChadDrop Pro.
- Works offline with a built-in rule engine; connect an AI proxy for fresher AI-generated reads.

ChadDrop is for entertainment and reflection. It is not therapy, legal advice, or a safety service. If a message feels threatening, contact someone you trust or local emergency services.

Privacy Policy: https://mvalasek77-droid.github.io/chaddrop-support/privacy.html

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## App Review Notes

ChadDrop has no account system. No sign-in or reviewer credentials are required.

To test:
1. Launch the app.
2. Paste a sample text message on the main screen.
3. Select a tone.
4. Tap Decode.
5. Tap the crown button to open ChadDrop Pro and confirm the weekly and annual subscription products load.
6. Open the Terms of Use and Privacy Policy links from the paywall.

The app is a humorous text decoder for entertainment. If online decoding is unavailable during review, the app falls back to local on-device decoding so the main experience remains testable. Purchase testing uses StoreKit/App Store sandbox products configured in App Store Connect.

Do not put API keys into the app binary, repository, App Review notes, or Resolution Center replies. If a future build requires server-backed AI for review, configure it through the server-side proxy and keep the provider key in server secrets only.

## Current Rejection Fixes

- Guideline 2.3.10: replace the public screenshot set with fresh iOS simulator screenshots from `AppStore/Screenshots/Public`. Do not upload release-gateway/internal screenshots or images with non-iOS status bars. Use "View All Sizes in Media Manager" and replace every device-size screenshot that still has an old status bar.
- Guideline 2.1(b): add `AppStore/Screenshots/IAPReview/chaddrop-pro-paywall.png` as the review screenshot for both subscription products, complete each product's localization/pricing/availability, attach both IAPs to app version `1.0`, and submit the IAPs with the new binary.
- Guideline 3.1.2(c): the paywall includes functional links to the Apple standard EULA and ChadDrop Privacy Policy. Add the Terms of Use link to the App Description and the Privacy Policy URL field in App Store Connect.
- Guideline 2.1 Information Needed: make clear in Review Notes that no account or reviewer credentials are needed for the offline/local decode build. If a future AI proxy build requires network AI, configure the proxy server-side instead of sharing provider keys with App Review.

## Subscriptions

Create one auto-renewable subscription group:

- Reference name: `ChadDrop Pro`
- Subscription level: Same level for weekly and yearly; the user receives the same entitlement from either duration.
- App bundle ID: `com.valasek.chaddrop`

Create these subscription products:

| Reference Name | Product ID | Duration | Price |
| --- | --- | --- | --- |
| ChadDrop Pro Weekly | `com.valasek.chaddrop.premium.weekly` | 1 week | `US$2.99` |
| ChadDrop Pro Annual | `com.valasek.chaddrop.premium.annual` | 1 year | `US$29.99` |

Subscription metadata to paste under English (U.S.) localization:

| Product ID | Display Name | Description |
| --- | --- | --- |
| `com.valasek.chaddrop.premium.weekly` | `ChadDrop Pro Weekly` | `Unlimited ChadDrop decodes and suggested replies for one week.` |
| `com.valasek.chaddrop.premium.annual` | `ChadDrop Pro Annual` | `Unlimited ChadDrop decodes and suggested replies for one year.` |

Subscription group display name:

```text
ChadDrop Pro
```

If App Store Connect still says Missing Metadata after saving the display name and description, add the subscription review screenshot under Review Information. A paywall screenshot is fine; it should show the ChadDrop Pro purchase options.

The weekly subscription price is set to `US$2.99`. The old yearly target was `US$24.99`; set the annual subscription price to `US$29.99` in App Store Connect. Do not change the Swift code for price changes. The app reads `displayPrice` from StoreKit.

For first-time subscription review, attach both subscription products to the new app version under the In-App Purchases and Subscriptions section before submitting the app. Apple will not allow the first subscriptions to be submitted standalone.

If the paywall says subscriptions are not available, check:
- Product IDs exactly match the table above.
- The subscriptions are in the same App Store Connect app as bundle ID `com.valasek.chaddrop`.
- Required metadata, localization, screenshot/review information, price, and availability are complete.
- Paid Apps agreement, tax, and banking are complete enough for Apple to make products available.
- Sandbox/TestFlight propagation has had time to update after metadata changes.

## Privacy Answers

### If shipping offline only

- Tracking: No
- Data collection: None
- Third-party advertising: No

### If shipping with AI proxy enabled

- Tracking: No
- Data linked to user: No, unless you later add accounts or identity logging
- Data used for tracking: No
- Data type: User Content
- Purpose: App Functionality
- Explanation: Pasted message text is sent to the configured AI proxy only to generate a decode result.

Do not log raw pasted messages in the proxy. Do not store OpenAI keys inside the iPhone app.

## URLs

- Support URL: `https://mvalasek77-droid.github.io/chaddrop-support/support.html`
- Privacy Policy URL: `https://mvalasek77-droid.github.io/chaddrop-support/privacy.html`
- Terms of Use (EULA): `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`
