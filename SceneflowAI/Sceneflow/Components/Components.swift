import SwiftUI

/// A glass card container used across screens.
struct GlassCard<Content: View>: View {
    var tier: GlassTier = .flat
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSurface(tier: tier) {
            AnyView(
                content().padding(padding)
            )
        }
    }
}

/// Primary filled button with the marquee gradient.
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: Palette.cornerMedium, style: .continuous)
                    .fill(Palette.marqueeGradient)
            )
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in Motion.run(.snap) { pressed = true } }
                .onEnded { _ in Motion.run(.snap) { pressed = false } }
        )
    }
}

/// Small pill label.
struct Pill: View {
    var text: String
    var color: Color = Palette.accent

    var body: some View {
        Text(text)
            .font(.labelSmall)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.8))
    }
}

/// Empty-state placeholder.
struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Palette.accent.opacity(0.8))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.primaryText)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// A section header with a trailing accessory.
struct SectionHeader<Accessory: View>: View {
    var title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.primaryText)
            Spacer()
            accessory()
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}
