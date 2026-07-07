# ChadDrop Xcode Cloud Setup

Use this when you want Apple to build and sign ChadDrop instead of setting up local signing on this Mac.

## What CodeGenie already prepared

- Xcode project: `TruthTranslator/TruthTranslator.xcodeproj`
- Scheme: `TruthTranslator`
- Bundle ID: `com.valasek.chaddrop`
- App name: `ChadDrop`
- CI scripts: `TruthTranslator/ci_scripts`
- Optional local secrets file: `TruthTranslator/Config/Secrets.xcconfig`

## What you must do in Apple screens

1. Open https://appstoreconnect.apple.com/apps.
2. Go to My Apps, press `+`, then choose `New App`.
3. Use these values:
   - Platform: `iOS`
   - Name: `ChadDrop`
   - Bundle ID: `com.valasek.chaddrop`
   - SKU: `CHADDROP-IOS-1`
4. Open `TruthTranslator/TruthTranslator.xcodeproj` in Xcode.
5. Open the Report Navigator, choose the Cloud tab, then press `Get Started`.
6. Grant Apple access to the GitHub repo when prompted.
7. Create a workflow named `Build & Test`.
8. Choose the branch you want Apple to build.
9. Add a Test action:
   - Scheme: `TruthTranslator`
   - Destination: recommended iPhone simulator destinations
10. Add an Archive action:
   - Scheme: `TruthTranslator`
   - Distribution: TestFlight internal testing
11. Save the workflow and watch the first build in App Store Connect -> Xcode Cloud.

## What cannot be automated safely

- Apple ID password entry
- Two-factor authentication codes
- Apple Developer enrollment or payments
- GitHub/App Store Connect permission prompts
- Legal agreements
- Final App Review submission

Apple documentation:

- https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/
- https://developer.apple.com/documentation/Xcode/Writing-Custom-Build-Scripts
