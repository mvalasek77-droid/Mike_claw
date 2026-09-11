# Auction Baby — Android (TWA)

A Trusted Web Activity wrapper that packages the Auction Baby PWA for the
Google Play Store. The app loads the live web app at
`mvalasek77.github.io/auctionbaby/app/` in a full-screen Chrome tab — no
browser UI, offline support via the service worker, and all existing features
work without changes.

## Prerequisites

- Android Studio Ladybug (2024.2+) or the Android SDK command-line tools
- JDK 17+
- A Google Play Developer account ($25 one-time)

## First-time setup

1. Open `AuctionBaby/android/` in Android Studio as an existing project.
2. Let Gradle sync and download dependencies.
3. Connect a device or start an emulator (API 24+).
4. Run the app — it should open the Auction Baby PWA full-screen.

## Digital Asset Links (required for full-screen TWA)

For the app to run without Chrome's URL bar, you need to verify domain
ownership via Digital Asset Links:

1. Generate a signing key (or use Play App Signing):
   ```bash
   keytool -genkeypair -v -keystore auctionbaby.keystore \
     -alias auctionbaby -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Get the SHA-256 fingerprint:
   ```bash
   keytool -list -v -keystore auctionbaby.keystore -alias auctionbaby \
     | grep SHA256
   ```

3. Replace `TODO:REPLACE_WITH_YOUR_SIGNING_KEY_SHA256_FINGERPRINT` in
   `web/.well-known/assetlinks.json` with the fingerprint.

4. If using Play App Signing (recommended), also add the Play-managed
   signing key fingerprint from the Play Console → Setup → App signing.

5. Deploy the web app so `assetlinks.json` is live at
   `https://mvalasek77.github.io/.well-known/assetlinks.json`

## Building a release APK / AAB

```bash
# Set signing config (or put in local.properties)
export KEYSTORE_FILE=path/to/auctionbaby.keystore
export KEYSTORE_PASSWORD=yourpassword
export KEY_ALIAS=auctionbaby
export KEY_PASSWORD=yourpassword

cd android
./gradlew bundleRelease   # produces app/build/outputs/bundle/release/app-release.aab
./gradlew assembleRelease # produces app/build/outputs/apk/release/app-release.apk
```

## Play Store submission

1. Go to play.google.com/console
2. Create a new app → "Auction Baby"
3. Upload the `.aab` file under Production → Create new release
4. Fill in the store listing:
   - Title: Auction Baby
   - Short description: Bid what a date is worth
   - Full description: An auction-house take on dating. Browse tonight's
     floor, place a bid on someone who catches your eye, and if they accept —
     you match and can start chatting.
   - Category: Dating
   - Content rating: complete the questionnaire
5. Add screenshots (phone + 7" tablet minimum)
6. Set pricing: Free (monetization via in-app Stripe checkout)
7. Submit for review

## How it works

The app is a thin Android shell around the existing PWA:

- **LauncherActivity** extends `androidbrowserhelper`'s TWA launcher
- Chrome renders the web app full-screen (no URL bar) when asset links verify
- The service worker handles offline caching
- Push notifications work via Web Push (VAPID) — no FCM needed
- Stripe checkout redirects work normally in the Chrome tab
- Email + password login works on all Android devices
- Sign in with Apple also works (Apple's JS SDK runs in the web view)

## Project structure

```
android/
├── app/
│   ├── build.gradle.kts          # Dependencies + signing config
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml    # TWA config, intent filters, asset links
│       ├── java/.../LauncherActivity.kt
│       └── res/
│           ├── drawable/splash.png
│           ├── mipmap-*/          # Launcher icons (all densities)
│           ├── values/            # Colors, strings, themes
│           └── xml/filepaths.xml
├── build.gradle.kts               # Root build file
├── settings.gradle.kts
├── gradle.properties
├── gradlew
└── gradle/wrapper/
```
