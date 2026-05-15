import SwiftUI

/// Tiny one-screen sheet shown the first time someone with zero ship
/// gates configured taps "Start a new build". The whole point: give
/// them an honest heads-up that the polish work is decoupled from the
/// build itself — they can either set things up now or come back later.
///
/// After dismissal we set `firstBuild.prompt.shown` so we don't nag.
struct FirstBuildPromptView: View {
    var onSetUp: () -> Void
    var onBuildNow: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LiquidGlass.warning)
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                    .padding(.top, 22)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Before your first build")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("To eventually send an app to the App Store you'll need an Apple Developer account, a Mac with Xcode, and (optionally) GitHub. We can walk you through all of that — about 10 minutes.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Set up shipping first", systemImage: "list.bullet.clipboard", style: .filled) {
                        Haptics.selection()
                        onSetUp()
                    }
                    PrimaryButton(title: "Build now, set up later", systemImage: "wand.and.stars", style: .glass) {
                        Haptics.selection()
                        onBuildNow()
                    }
                    Button("Cancel") {
                        Haptics.selection()
                        onCancel()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
