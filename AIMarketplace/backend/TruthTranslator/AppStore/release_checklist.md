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
- Create the App Store Connect app placeholder before uploading the first build.
- Confirm App Store privacy answers match the deployed proxy behavior.
- Review the mild crude humor against App Review guideline expectations.
- Replace `support@example.com` in `Web/support.html` before publishing the support site.

## Suggested archive command
```sh
xcodebuild -project TruthTranslator.xcodeproj -scheme TruthTranslator -configuration Release -destination generic/platform=iOS archive
```
