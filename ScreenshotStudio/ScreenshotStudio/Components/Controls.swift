import SwiftUI

/// A labelled slider row with a live value read-out, styled for glass panels.
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Spacer()
                Text(format(value))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
            Slider(value: $value, in: range) { editing in
                if editing { Haptics.selection() }
            }
            .tint(LiquidGlass.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
    }
}

/// A glass-styled toggle row.
struct ToggleRow: View {
    let label: String
    var systemImage: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LiquidGlass.accent)
                }
                Text(label)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
        .tint(LiquidGlass.accent)
        .onChange(of: isOn) { _, _ in Haptics.selection() }
    }
}

/// A compact, equal-width segmented control that adopts the glass aesthetic.
struct GlassSegmented<T: Hashable>: View {
    /// Each option is a (value, label) pair. Unlabeled tuples keep call sites
    /// terse while sidestepping generic tuple-label coercion quirks.
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option in
                let value = option.0
                let isSelected = value == selection
                Button {
                    Motion.run(Motion.snap) { selection = value }
                    Haptics.selection()
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : LiquidGlass.primaryText.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Group {
                                if isSelected {
                                    Capsule().fill(LiquidGlass.auroraGradient.opacity(0.9))
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }
}
