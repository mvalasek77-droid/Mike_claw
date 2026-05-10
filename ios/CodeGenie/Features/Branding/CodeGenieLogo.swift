import SwiftUI

/// CodeGenie's logo: a stylised genie spilling out of a curly-brace lamp.
/// Drawn entirely in SwiftUI so it scales without raster assets and adopts
/// the user's color scheme automatically.
struct CodeGenieLogo: View {
    var size: CGFloat = 120
    var animate: Bool = true

    @State private var floating = false
    @State private var sparkleSpin = false

    var body: some View {
        ZStack {
            // Soft glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [LiquidGlass.accent.opacity(0.55), .clear],
                        center: .center, startRadius: 0, endRadius: size * 0.7
                    )
                )
                .blur(radius: size * 0.06)
                .scaleEffect(floating ? 1.06 : 1.0)

            // Lamp — a glassy '{' on the left and '}' on the right
            HStack(spacing: -size * 0.10) {
                Text("{")
                    .font(.system(size: size * 0.78, weight: .black, design: .rounded))
                    .foregroundStyle(LiquidGlass.auroraGradient)
                    .shadow(color: LiquidGlass.accent.opacity(0.45), radius: size * 0.05, y: 4)
                Text("}")
                    .font(.system(size: size * 0.78, weight: .black, design: .rounded))
                    .foregroundStyle(LiquidGlass.auroraGradient)
                    .shadow(color: LiquidGlass.accentSecondary.opacity(0.45), radius: size * 0.05, y: 4)
            }
            .offset(y: size * 0.04)

            // Wisp of smoke / genie — three rising arcs
            wisp(yOffset: -size * 0.32, scale: 0.7, opacity: 0.85)
            wisp(yOffset: -size * 0.16, scale: 1.0, opacity: 0.95)

            // Star sparkle, slowly rotating
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.6), radius: size * 0.04)
                .rotationEffect(.degrees(sparkleSpin ? 360 : 0))
                .offset(x: size * 0.30, y: -size * 0.32)

            // Genie eye — a single shining dot for personality
            Circle()
                .fill(.white)
                .frame(width: size * 0.05, height: size * 0.05)
                .offset(x: -size * 0.05, y: -size * 0.20)
                .shadow(color: .white.opacity(0.8), radius: size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("CodeGenie logo")
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { floating = true }
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) { sparkleSpin = true }
        }
    }

    private func wisp(yOffset: CGFloat, scale: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [LiquidGlass.accentSecondary.opacity(opacity),
                             LiquidGlass.accent.opacity(opacity * 0.6)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: size * 0.28 * scale, height: size * 0.18 * scale)
            .blur(radius: size * 0.012)
            .offset(y: yOffset + (floating ? -size * 0.02 : size * 0.02))
            .opacity(opacity)
    }
}

/// Bigger marquee version for splash / onboarding hero.
struct CodeGenieMark: View {
    var body: some View {
        VStack(spacing: 14) {
            CodeGenieLogo(size: 132)
            Text("CodeGenie")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Build apps from your phone.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

#Preview {
    ZStack {
        LiquidGlassBackground().ignoresSafeArea()
        CodeGenieMark()
    }
}
