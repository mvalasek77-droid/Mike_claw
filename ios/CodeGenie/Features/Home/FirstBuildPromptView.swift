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
                    Text("Good to know before you start")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Building your app needs only this phone. Putting it on a real iPhone or the App Store also needs a Mac with Xcode and Apple's developer program ($99 a year). You can build now and sort that out later — CodeGenie walks you through it.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    // Building needs nothing but an idea, so that comes
                    // first. Asking a newcomer to install Xcode before
                    // they have seen the product do anything loses them.
                    PrimaryButton(title: "Build my app first", systemImage: "wand.and.stars", style: .filled) {
                        Haptics.selection()
                        onBuildNow()
                    }
                    PrimaryButton(title: "Set up my Mac first", systemImage: "macbook", style: .glass) {
                        Haptics.selection()
                        onSetUp()
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
