import SwiftUI

/// A fully runnable, pre-baked "Tide Times" sample app the user can
/// open from HomeView in <30 seconds. This is the **Instant Value
/// 2/10 → 7+/10** fix per the competitive critique: previously
/// "Try a sample" played a video of one being built; now it shows
/// a finished, working app on the user's actual phone.
///
/// No backend, no Mac companion, no AI call. The whole thing runs
/// from a synthetic data set so it can boot in well under a second
/// — exactly the dopamine moment the audit flagged as missing.
struct TideTimesPreview: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSpot: TideSpot = .ocean
    @State private var now: Date = Date()
    @State private var heroOpacity: Double = 0

    private let tides: [TideEntry] = TideEntry.fakeDay()

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard
                        spotPicker
                        todayTimeline
                        weeklyOverview
                        whatIsThisCard
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { heroOpacity = 1 }
            Haptics.success()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Surfaces

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.08, blue: 0.18),
                Color(red: 0.06, green: 0.18, blue: 0.32),
                Color(red: 0.10, green: 0.34, blue: 0.56),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.white.opacity(0.12), in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Close sample")
            Spacer()
            VStack(spacing: 2) {
                Text("Sample app")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text("Tide Times")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .semibold))
                .padding(10)
                .background(.white.opacity(0.12), in: Circle())
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var heroCard: some View {
        VStack(spacing: 8) {
            Text(selectedSpot.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1.4)
            Text(tides.current(at: now).heightString)
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(tides.current(at: now).descriptor)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 6) {
                Image(systemName: tides.current(at: now).trending)
                    .font(.system(size: 12, weight: .bold))
                Text("Next \(tides.next(after: now).label) · \(tides.next(after: now).timeString)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                )
        )
        .opacity(heroOpacity)
    }

    private var spotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TideSpot.allCases) { spot in
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            selectedSpot = spot
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: spot.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(spot.label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(
                            (selectedSpot == spot ? Color.white.opacity(0.20) : Color.white.opacity(0.06)),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(.white.opacity(selectedSpot == spot ? 0.5 : 0.15), lineWidth: 0.8))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSpot == spot ? .isSelected : [])
                }
            }
        }
    }

    private var todayTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                ForEach(tides) { entry in
                    VStack(spacing: 6) {
                        Text(entry.timeString)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                        Image(systemName: entry.icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(entry.tint)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(entry.tint.opacity(0.18)))
                        Text(entry.heightString)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(entry.label)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 4) {
                ForEach(Day.week) { day in
                    HStack {
                        Text(day.short)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, alignment: .leading)
                        WaveBar(highMeters: day.highM, lowMeters: day.lowM)
                            .frame(height: 18)
                        Text(String(format: "%.1fm", day.highM))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
    }

    private var whatIsThisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LiquidGlass.accent)
                Text("This is a sample built with CodeGenie")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("Everything you see — the gradient, the tide chart, the haptic feel — was generated end-to-end from a one-line prompt. Yours will look the way you describe it.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

// MARK: - Synthetic data

private struct WaveBar: View {
    let highMeters: Double
    let lowMeters: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(0.1, highMeters - lowMeters)
            let highW = min(1, span / 4)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.cyan.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * highW)
            }
        }
    }
}

private enum TideSpot: String, CaseIterable, Identifiable {
    case ocean, harbour, reef
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ocean:   return "Ocean Beach"
        case .harbour: return "Harbour Mouth"
        case .reef:    return "Outer Reef"
        }
    }
    var icon: String {
        switch self {
        case .ocean:   return "water.waves"
        case .harbour: return "ferry"
        case .reef:    return "fish"
        }
    }
}

private struct TideEntry: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let heightM: Double
    let label: String

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
    var heightString: String { String(format: "%.1f m", heightM) }
    var descriptor: String {
        switch label {
        case "High":   return "Peak surf window"
        case "Low":    return "Tidepool time"
        default:       return "Mid tide"
        }
    }
    var icon: String {
        switch label {
        case "High":  return "arrow.up.right"
        case "Low":   return "arrow.down.right"
        default:      return "arrow.right"
        }
    }
    var tint: Color {
        switch label {
        case "High":  return .cyan
        case "Low":   return .orange
        default:      return .blue
        }
    }
    var trending: String {
        heightM > 1.5 ? "arrow.up.right" : "arrow.down.right"
    }

    static func fakeDay() -> [TideEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return [
            .init(date: start.addingTimeInterval(2 * 3600  + 10 * 60), heightM: 0.5, label: "Low"),
            .init(date: start.addingTimeInterval(8 * 3600  + 25 * 60), heightM: 1.9, label: "High"),
            .init(date: start.addingTimeInterval(14 * 3600 + 40 * 60), heightM: 0.6, label: "Low"),
            .init(date: start.addingTimeInterval(20 * 3600 + 55 * 60), heightM: 2.1, label: "High"),
        ]
    }
}

private extension Array where Element == TideEntry {
    func current(at date: Date) -> TideEntry {
        // Return the most recent past entry, falling back to first.
        let past = filter { $0.date <= date }
        return past.last ?? self[0]
    }
    func next(after date: Date) -> TideEntry {
        first { $0.date > date } ?? self[self.count - 1]
    }
}

private struct Day: Identifiable {
    let id = UUID()
    let short: String
    let highM: Double
    let lowM: Double
    static let week: [Day] = [
        .init(short: "Mon", highM: 1.9, lowM: 0.5),
        .init(short: "Tue", highM: 2.1, lowM: 0.4),
        .init(short: "Wed", highM: 2.3, lowM: 0.3),
        .init(short: "Thu", highM: 2.2, lowM: 0.4),
        .init(short: "Fri", highM: 2.0, lowM: 0.5),
        .init(short: "Sat", highM: 1.8, lowM: 0.6),
        .init(short: "Sun", highM: 1.7, lowM: 0.7),
    ]
}
