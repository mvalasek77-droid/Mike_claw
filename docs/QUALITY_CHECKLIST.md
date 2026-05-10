# CodeGenie Quality Checklist

Apple is cracking down on "vibe coded" apps. Every release CodeGenie ships
— and every app *built by* CodeGenie — must clear this list.

## 1. Functionality

- [ ] All features in the spec work end-to-end on a real device
- [ ] No half-finished flows; every button leads somewhere meaningful
- [ ] No demo data shipping in production builds
- [ ] No commented-out code, no `// TODO`s, no `print` debugging
- [ ] Force-unwraps audited and replaced with `guard let` where appropriate

## 2. Tested rigorously

- [ ] iPhone 16 (latest), iPhone SE (small), iPhone 16 Pro Max (large) flows
- [ ] Cold start, warm start, background → foreground
- [ ] Offline path, slow network (Network Link Conditioner: 3G)
- [ ] Memory profile clean (no leaks in Instruments → Leaks)
- [ ] Cold-start time < 1.5s on iPhone SE
- [ ] No hangs reported by MetricKit during a 10-minute soak

## 3. Polish

- [ ] Every animation eases — no linear interpolation on UI
- [ ] All transitions respect `@Environment(\.accessibilityReduceMotion)`
- [ ] Haptics calibrated (Core Haptics for transient, UIKit fallback only on older devices)
- [ ] Empty states designed, not blank
- [ ] Loading states use shimmer / skeletons, not stalled spinners

## 4. Accessibility

- [ ] Every interactive view has an `accessibilityLabel`
- [ ] Decorative views are `.accessibilityHidden(true)`
- [ ] VoiceOver flow tested for the golden path
- [ ] Dynamic Type up to AX5 — no truncation
- [ ] Contrast ratio ≥ 4.5:1 for body text in both color schemes

## 5. Dark mode

- [ ] Every screen tested in light + dark
- [ ] Semantic colors only (no hard-coded hex outside the design system)
- [ ] Asset catalog appearances configured
- [ ] Glass surfaces don't lose contrast against dark backdrops

## 6. Liquid Glass / iOS 26

- [ ] Glass surfaces use `.glassEffect(.regular)` on iOS 26+
- [ ] Graceful fallback to `.ultraThinMaterial` on iOS 17–25
- [ ] Adaptive haptics (Core Haptics where available)
- [ ] Depth effects: parallax-aware shadows, no flat drops
- [ ] Subtle 0.5–1pt white edge stroke on every glass surface

## 7. Senior-engineer code review

- [ ] No retain cycles (every `[weak self]` justified)
- [ ] `@MainActor` discipline on UI-mutating code
- [ ] Error paths handled, not just happy paths
- [ ] No premature abstractions; concrete code preferred
- [ ] Dependencies audited — no unmaintained packages

## 8. App Store readiness

- [ ] 1024×1024 PNG icon, sRGB, **no alpha**, no rounded corners
- [ ] Screenshots for 6.7" + 6.1"
- [ ] Privacy nutrition label complete
- [ ] Export-compliance question answered (typically "No")
- [ ] Marketing copy ≤ 4000 chars, keywords ≤ 100 chars
- [ ] Support URL responds 200

## 9. CodeGenie-specific gates

- [ ] Genie Swarm reviewer raises **zero** `critical` findings
- [ ] Genie Swarm security auditor raises **zero** `critical` findings
- [ ] Build green on the remote runner before user is asked to test
- [ ] Diff visibly previewed before any file write
- [ ] Tetris (BitDrop) loads in < 200ms during build screen
