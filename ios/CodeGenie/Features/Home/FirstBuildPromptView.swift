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
                    Text("Two paths from here")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("CodeGenie can build your app on its own. Sending it to the App Store needs a Mac with Xcode and an Apple Developer account ($99/yr). We'll walk you through that — but it's also OK to build first and decide later.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "Start with Xcode (10 min)", systemImage: "list.bullet.clipboard", style: .filled) {
                        Haptics.selection()
                        onSetUp()
                    }
                    PrimaryButton(title: "Just build something — I'll set up shipping later", systemImage: "wand.and.stars", style: .glass) {
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
