# CodeGenie — Distribution Readiness

Honest assessment of the iOS app (`ios/CodeGenie`, ~14.3k lines of Swift) ahead
of App Store submission. Written from a **source-level audit** — this pass was
done in a Linux container with no Xcode and no Swift toolchain, so nothing here
was compiled or run. Anything that requires building, the Simulator, a device,
or App Store Connect is called out explicitly as **needs a Mac**.

The goal you set: "polish so it looks senior-engineer-based, not vibe-coded."
Good news — by inspection, it already does. The findings below are about
finishing the last mile, not rescuing a mess.

---

## Verdict

| Question | Answer |
|---|---|
| Does the code look senior-engineer-based? | **Yes.** Coherent design system, Reduce-Motion correctness, Core Haptics with graceful fallback, availability-gated iOS 26 glass, complete privacy manifest. No debug `print`s, no `TODO`/`FIXME`, no crash-risk force-unwraps. |
| Is it *certified* zero-bug and ready to ship today? | **No — and no static review can certify that.** Two submission blockers below, plus a required build-and-run pass on a Mac. |
| Biggest risk to approval? | The legal links (see Blocker 1). Not the code quality. |

---

## What I verified by inspection (holds up)

- **Design system is one coherent family.** `Theme/LiquidGlass.swift` centralizes
  materials, gradients, corners, and motion; screens compose `GlassSurface`
  tiers rather than reinventing chrome. This is the single biggest "not
  vibe-coded" signal to a reviewer.
- **Accessibility is real, not bolted on.** `Motion.run` and the `.motion(_:value:)`
  modifier collapse to no-ops under Reduce Motion; the animated background
  freezes to a static pose instead of burning battery; tab items carry
  `accessibilityLabel` + `.isSelected`; the ASC automation badges have spoken
  labels.
- **Dark mode + light mode both designed for** — `primaryText` and the base
  gradients branch on `colorScheme`, not a single hardcoded palette.
- **Haptics degrade gracefully** — Core Haptics where supported, UIKit
  generators otherwise; no assumption of hardware.
- **Privacy is complete** — `Info.plist` has camera, local-network, and
  photo-add usage strings (all honestly worded), `ITSAppUsesNonExemptEncryption`
  is set (skips the export-compliance prompt), Bonjour services are declared,
  and a `PrivacyInfo.xcprivacy` manifest is present (App Review now requires it).
- **No obvious crash surface** — the only `fatalError` is the idiomatic
  `init?(coder:)` stub; `URL(string:)!` force-unwraps are all on hardcoded valid
  literals; no `try!`/`as!` in app code.

## Fixed in this pass

- **Glass corner-radius mismatch** (`Theme/LiquidGlass.swift`) — the iOS 26
  `glassEffect` clip was hardcoded to radius 28, so smaller glass surfaces
  (chips, badges, medium/small cards) got a clip that didn't match their own
  corner on iOS 26. Now threads the surface's actual `corner` through. Pure
  polish, exactly the kind of seam a reviewer notices.

---

## Blockers before submission (real, and not code-quality)

### 1. Legal links must be live — likely rejection otherwise
`Features/Onboarding/TermsAndPrivacyView.swift` links to
`https://codegenie.app/terms` and `https://codegenie.app/privacy`. App Review
opens these; if the domain doesn't serve real Terms and Privacy pages, that's a
**Guideline 5.1.1 / 1.5 rejection**. Note the hosted legal pages created earlier
in `docs/` are for **Claude Prompt Coach**, a different app — they do **not**
cover CodeGenie. Action: confirm `codegenie.app/terms` and `/privacy` are live
with CodeGenie-specific content, or point the links at pages that are.

### 2. Version is 0.1.0 (build 1)
`Info.plist` ships `CFBundleShortVersionString 0.1.0`. That submits fine, but a
`0.x` marketing version signals "beta" to some reviewers. Consider `1.0.0` for
the first public release. Mechanical, but decide it deliberately.

---

## Needs a Mac (cannot be verified from here — the real "final test")

None of these are optional; they're the part of "final test" a Linux box can't do.

1. **Build clean in Xcode** with the iOS 26 SDK — the code gates `glassEffect`
   behind `#available` + `#if compiler(>=6.2)`, so confirm both the iOS 26 path
   and the fallback compile with **zero warnings** (warnings read as sloppiness).
2. **Run every flow in the Simulator**, at minimum: Splash → Onboarding →
   Terms → Home; Build (Describe sheet → kickoff); Play; Apps gallery; Settings
   incl. Pair-Mac / QR scanner; the ASC guide step-through.
3. **Edge cases:** first launch (empty state), Reduce Motion ON, Dynamic Type at
   the largest accessibility size (check the tab labels and step cards don't
   truncate badly), Dark and Light, iPad layout (portrait + the landscape
   orientations the plist allows), offline / airplane mode on any network call.
4. **Performance:** the `TimelineView` background at 30fps and the `BitDrop`
   game — profile with Instruments for dropped frames and battery; verify the
   background pauses when off-screen.
5. **Device haptics** — Core Haptics can't be judged in the Simulator; feel
   `tap`, `shimmer`, `success` on a real iPhone.
6. **VoiceOver sweep** — turn it on and navigate each screen end to end.

---

## App Review rejection triggers — pre-submission checklist

These are the patterns Apple actually rejects "AI-generated-looking" apps on.
Walk this before submitting:

- [ ] Terms & Privacy URLs live and app-specific (Blocker 1).
- [ ] No placeholder/lorem text, no "Coming soon" dead ends, no buttons that do
      nothing — every control reaches a real state.
- [ ] Any account/API-key entry has a working path and a stated purpose; if the
      app needs the user's own key, the App Review notes must say so and provide
      a demo path or test key.
- [ ] App works (or degrades honestly) without the Mac companion paired — a
      reviewer won't have your Mac. Confirm the Pair-Mac and ASC flows show a
      clear "pair first" state rather than failing silently.
- [ ] Screenshots are real app screens (the app renders them from the Simulator
      walkthrough — good — just confirm they're current).
- [ ] No private API use, no undocumented entitlements.
- [ ] Crash-free launch on the oldest supported iOS version, not just iOS 26.
- [ ] Support URL and marketing contact resolve.

---

## Bottom line

The engineering quality is not the problem — this reads as a real app built by
someone who knows SwiftUI and the platform. To get to submittable: fix the two
blockers above, then do the Mac-only build/run/VoiceOver/Instruments pass. I can
keep hardening specific screens from source (accessibility labels, Dynamic Type,
empty states) — tell me which flow matters most and I'll go deep on it. What I
cannot do from this environment is press Build, and I won't tell you it's
"tested and zero bugs" when it hasn't been run.
