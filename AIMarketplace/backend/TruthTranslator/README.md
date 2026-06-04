# ChadDrop

A SwiftUI iOS app that lets users paste confusing texts and get a funny, psychology-informed translation, truth score, and suggested replies.

The app is simulator-ready without network access using a local decode engine. For production AI output, configure `AI_PROXY_URL` in the xcconfig files and deploy `Proxy/openai-worker.js` with an `OPENAI_API_KEY` server secret.

## Beginner Release Gateway

Open the no-code release guide:

```sh
Scripts/open_release_gateway.sh
```

It includes signing steps, App Store Connect copy/paste values, privacy answers, screenshot automation, and GitHub Pages support-site setup.

## Build

```sh
xcodegen generate
xcodebuild -project TruthTranslator.xcodeproj -scheme TruthTranslator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build
```

## Test

```sh
xcodebuild -project TruthTranslator.xcodeproj -scheme TruthTranslator -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
```

## App Store

See `AppStore/ChadDrop_Release_Gateway.html`, `AppStore/app_store_connect_answers.md`, `AppStore/metadata.md`, `AppStore/privacy.md`, and `AppStore/release_checklist.md`.
