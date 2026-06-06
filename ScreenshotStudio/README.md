# Screenshot Studio

Turn raw iPhone screenshots into **App Store Connect–ready** marketing
screenshots — framed, captioned, and rendered at exactly the pixel sizes Apple
validates against, so uploads pass on the first try.

A SwiftUI app built to a senior-engineer bar: a pure, unit-tested rendering
core; a WYSIWYG preview that is literally the same view the exporter renders;
and an iOS 26 Liquid Glass design language with adaptive haptics, depth, and
full Reduce-Motion / dark-mode / Dynamic-Type support.

> The name is deliberately literal — anyone who reads "Screenshot Studio"
> knows exactly what it does.

## What it does

1. **Import** any screenshot straight from your iPhone (PHPicker, no full
   library access required).
2. **Frame** it in a device bezel over a tasteful gradient or solid backdrop.
3. **Caption** it with a marketing headline (auto-contrast or custom color).
4. **Export** every required App Store Connect size at exact pixels, saved to
   a dedicated "Screenshot Studio" Photos album, ready to upload.

## App Store Connect sizes

Rendered at the exact resolutions Apple validates:

| Slot | Resolution (portrait) | Required |
|------|----------------------|----------|
| iPhone 6.9" | 1320 × 2868 | ✅ |
| iPhone 6.7" | 1290 × 2796 | |
| iPhone 6.5" | 1242 × 2688 | ✅ |
| iPhone 5.5" | 1242 × 2208 | |
| iPad 13"    | 2064 × 2752 | ✅ |
| iPad 12.9"  | 2048 × 2732 | |

## Architecture

```
ScreenshotStudio/
├─ App/           App entry, root routing, global AppState
├─ Theme/         Liquid Glass design system (materials, motion, haptics, type)
├─ Components/    Reusable glass UI (cards, buttons, controls, pickers)
├─ Models/        ASCDeviceSize, CanvasStyle, ScreenshotProject  (pure data)
├─ Services/      Composer (pure layout math), Renderer, stores, exporter
├─ Features/      Onboarding · Branding · Studio · Projects · Guide · Settings
└─ Resources/     Info.plist, privacy manifest, asset catalog, app icon
```

**The core is deliberately UIKit-free and pure:**
`ScreenshotComposer.layout(canvas:style:sourceSize:)` computes every rect in
the target's pixel space. The on-screen preview and the off-screen exporter
both feed that math into the **same** `ScreenshotCanvas` view, so the preview
is genuinely what exports — never an approximation. That purity is what makes
the behaviour fast to unit-test (`ScreenshotStudioTests/`).

## Building

The project is generated from `project.yml` (XcodeGen) and a committed,
deterministic `ScreenshotStudio.xcodeproj` so it opens on a fresh clone with no
tooling.

```bash
# Open directly:
open ScreenshotStudio.xcodeproj

# Or regenerate the project file:
xcodegen generate                       # if you have XcodeGen
python3 Scripts/generate_xcodeproj.py   # zero-dependency fallback

# Regenerate the app icon:
python3 Scripts/generate_app_icon.py
```

Requirements: Xcode 16, iOS 17+ deployment target (Liquid Glass effects light
up on iOS 26).

## Tests

`ScreenshotStudioTests/` pins down the rendering core:

- `ScreenshotComposerTests` — aspect-fit math, caption bands, bezel/corner
  geometry, clamping, and "device always fits the canvas" invariants.
- `ASCDeviceSizeTests` — exact required resolutions, orientation swap, labels.
- `ModelCodableTests` — project JSON round-trips, export de-duplication,
  caption override precedence, color/luminance math.

Run with **⌘U** in Xcode, or `xcodebuild test -scheme ScreenshotStudio`.

## Privacy

Everything runs on-device. Screenshots never leave the phone, there are no
accounts, no networking, and no analytics. See `Resources/PrivacyInfo.xcprivacy`.

## Roadmap

Surfaced in-app under the **Guide** tab: text/sticker overlays, a template
gallery, localized caption sets, and App Preview video framing.
