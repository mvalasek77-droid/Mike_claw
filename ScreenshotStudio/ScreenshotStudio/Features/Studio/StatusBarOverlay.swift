import SwiftUI

/// A clean, synthetic iOS status bar drawn over the top of a screenshot, sized
/// in the screenshot's pixel space so it renders identically in preview and
/// export. Layout adapts per device class (Dynamic Island, notch, classic
/// iPhone, iPad).
struct StatusBarOverlay: View {
    let kind: StatusBarLayoutKind
    let style: StatusBarStyle
    /// Width of the screen opening in pixels — every metric scales from this.
    let width: CGFloat
    /// Opaque fill drawn behind the bar to cover the screenshot's own status
    /// bar (sampled from the screenshot's top edge).
    var fill: Color = .clear
    /// Whether that fill is light (so glyphs go dark) — used for `.auto`.
    var fillIsLight: Bool = false

    private var glyph: Color {
        switch style.appearance {
        case .light: return .white
        case .dark: return Color(white: 0.08)
        case .auto: return fillIsLight ? Color(white: 0.08) : .white
        }
    }
    private var barHeight: CGFloat { width * (kind == .pad ? 0.045 : 0.125) }
    private var fontSize: CGFloat { width * (kind == .pad ? 0.022 : 0.045) }
    private var iconSize: CGFloat { width * (kind == .pad ? 0.024 : 0.05) }
    private var hPadding: CGFloat { width * (kind.isModern ? 0.085 : 0.05) }
    /// Modern bars sit lower (under the sensor housing); classic ones center.
    private var contentTopBias: CGFloat { kind.isModern ? barHeight * 0.34 : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            if kind.hasIsland {
                Capsule()
                    .fill(Color.black)
                    .frame(width: width * 0.30, height: barHeight * 0.34)
                    .padding(.top, barHeight * 0.30)
            }

            content
                .padding(.horizontal, hPadding)
                .padding(.top, contentTopBias)
                .frame(height: barHeight)
        }
        .frame(width: width, height: barHeight, alignment: .top)
        .background(fill)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if kind.isModern {
            // Time left · status cluster right.
            HStack(alignment: .center) {
                timeText
                Spacer(minLength: 0)
                cluster
            }
        } else {
            // Classic: signal/carrier left · time center · battery right.
            ZStack {
                timeText.frame(maxWidth: .infinity, alignment: .center)
                HStack {
                    HStack(spacing: width * 0.012) {
                        if style.showCellular { icon("cellularbars") }
                        if style.showCarrier {
                            Text(style.carrier)
                                .font(.system(size: fontSize * 0.82, weight: .regular))
                                .foregroundStyle(glyph)
                                .lineLimit(1)
                        }
                        if style.showWiFi { icon("wifi") }
                    }
                    Spacer(minLength: 0)
                    batteryCluster
                }
            }
        }
    }

    private var timeText: some View {
        Text(style.time)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(glyph)
            .lineLimit(1)
    }

    private var cluster: some View {
        HStack(spacing: width * 0.018) {
            if style.showCellular { icon("cellularbars") }
            if style.showWiFi { icon("wifi") }
            batteryCluster
        }
    }

    private var batteryCluster: some View {
        HStack(spacing: width * 0.012) {
            if style.showBatteryPercent {
                Text("\(min(max(style.batteryPercent, 0), 100))%")
                    .font(.system(size: fontSize * 0.82, weight: .medium))
                    .foregroundStyle(glyph)
            }
            icon(batterySymbol)
        }
    }

    private var batterySymbol: String {
        switch min(max(style.batteryPercent, 0), 100) {
        case ...10: return "battery.0"
        case ...37: return "battery.25"
        case ...62: return "battery.50"
        case ...87: return "battery.75"
        default: return "battery.100"
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(glyph)
    }
}
