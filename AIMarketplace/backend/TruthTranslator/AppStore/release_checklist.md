# Release Checklist

Start with the beginner gateway:

```sh
Scripts/open_release_gateway.sh
```

## Automated locally
- Generate the Xcode project with `xcodegen generate`.
- Create and validate the app icon with `Scripts/create_app_icon.sh`.
- Run unit tests and UI tests on iOS Simulator.
- Build Debug for simulator.
- Build or archive Release after signing is configured.
- Install and launch the simulator app.
- Capture simulator screenshots with `Scripts/capture_appstore_screenshots.sh`.

## Required before App Store upload
- Set `DEVELOPMENT_TEAM` in `Config/Release.xcconfig`.
- Set `AI_PROXY_URL` in `Config/Release.xcconfig` if shipping AI-backed responses.
- Deploy the proxy with `OPENAI_API_KEY` stored as a server secret, not in the iOS app.
- Add production screenshots.
- Replace any rejected screenshots with fresh images from `AppStore/Screenshots/Public`; do not upload `InternalWalkthrough` images.
- Open "View All Sizes in Media Manager" and replace every stale screenshot size that still shows a non-iOS or simulator status bar.
- Set Support URL to `https://mvalasek77-droid.github.io/chaddrop-support/support.html`.
- Set Privacy Policy URL to `https://mvalasek77-droid.github.io/chaddrop-support/privacy.html`.
- Add `Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` to the App Description or EULA field.
- Create the App Store Connect app placeholder before uploading the first build.
- Create the `ChadDrop Pro` auto-renewable subscription group with `com.valasek.chaddrop.premium.weekly` and `com.valasek.chaddrop.premium.annual`.
- Add English (U.S.) display names and descriptions for both subscription products.
- Set the weekly subscription price to `US$2.99` in App Store Connect.
- Set the annual subscription price to `US$29.99` in App Store Connect.
- Upload `AppStore/Screenshots/IAPReview/chaddrop-pro-paywall.png` as the App Review screenshot for both subscriptions.
- Attach the first subscription products to the app version before the first App Review submission.
- For this resubmission, upload build `1.0.0 (11)` or higher because Apple already reviewed `1.0 (10)` on July 7, 2026.
- In App Review notes, state that the app includes functional Terms of Use and Privacy Policy links in the main app footer and ChadDrop Pro purchase flow, then attach a short screen recording that taps both links.
- Do not share provider API keys in App Review notes/messages or source. For the offline/local build, state that no API key is needed; for a future AI-backed build, keep the provider key in server-side proxy secrets.
- Confirm App Store privacy answers match the deployed proxy behavior.
- Review the mild crude humor against App Review guideline expectations.

## Suggested archive command
```sh
xcodebuild -project TruthTranslator.xcodeproj -scheme TruthTranslator -configuration Release -destination generic/platform=iOS archive
```
