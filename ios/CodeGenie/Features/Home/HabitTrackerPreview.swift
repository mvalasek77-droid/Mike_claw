import SwiftUI

/// Pre-baked Habit Tracker sample app. Warm/orange palette, streak
/// dopamine — counterpoint to the cool TideTimes ocean look. Part
/// of the Instant Grade rail (Kino-pattern: a row of one-tap
/// finished samples on HomeView so a first-timer hits "oh wow" in
/// under a second).
///
/// Synthetic data, no backend, no AI call. Designed to feel like a
/// finished app you'd buy on the App Store — not a mockup.
struct HabitTrackerPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var habits: [Habit] = Habit.starterSet()
    @State private var celebratedHabitID: UUID?

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard
                        todayHeader
                        habitList
                        weekStreaks
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
        .onAppear { Haptics.success() }
        .accessibilityElement(children: .contain)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.06, blue: 0.02),
                Color(red: 0.36, green: 0.14, blue: 0.04),
                Color(red: 0.58, green: 0.28, blue: 0.10),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { Haptics.selection(); dismiss() } label: {
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
                    .textCase(.uppercase).tracking(1.2)
                Text("Streak")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .padding(10)
                .background(.white.opacity(0.12), in: Circle())
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private var heroCard: some View {
        let total = habits.count
        let done = habits.filter { $0.doneToday }.count
        return VStack(spacing: 6) {
            Text(Date(), format: .dateTime.weekday(.wide).month().day())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase).tracking(1.2)
            Text("\(done) / \(total)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(done == total ? "Day complete — nice work" : "\(total - done) habits left today")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(habits.map(\.streakDays).max() ?? 0) day streak")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
        )
    }

    private var todayHeader: some View {
        Text("Today")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var habitList: some View {
        VStack(spacing: 8) {
            ForEach($habits) { $habit in
                Button {
                    Haptics.success()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        habit.doneToday.toggle()
                        if habit.doneToday {
                            habit.streakDays += 1
                            celebratedHabitID = habit.id
                        } else if habit.streakDays > 0 {
                            habit.streakDays -= 1
                        }
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(habit.doneToday ? AnyShapeStyle(habit.tint) : AnyShapeStyle(Color.white.opacity(0.08)))
                                .frame(width: 36, height: 36)
                            Image(systemName: habit.doneToday ? "checkmark" : habit.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .strikethrough(habit.doneToday, color: .white.opacity(0.5))
                            Text("\(habit.streakDays) day streak")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        if habit.doneToday {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white.opacity(habit.doneToday ? 0.10 : 0.05))
                    )
                    .scaleEffect(celebratedHabitID == habit.id ? 1.03 : 1)
                    .animation(.spring(response: 0.3), value: celebratedHabitID)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(habit.doneToday ? "\(habit.title), done, \(habit.streakDays) day streak" : "\(habit.title), \(habit.streakDays) day streak, tap to mark done")
            }
        }
    }

    private var weekStreaks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(["S","M","T","W","T","F","S"][i])
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(weekFill(i))
                            .frame(height: 36)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
    }

    private func weekFill(_ index: Int) -> Color {
        // Fake heatmap — earlier days got more done; today is partial.
        switch index {
        case 0, 6: return .orange.opacity(0.20)
        case 1...4: return .orange.opacity(0.85)
        case 5: return .orange.opacity(0.55)
        default: return .white.opacity(0.08)
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
            Text("Tap a habit to feel the streak haptic. Every pixel — gradient, heatmap, the way the count bumps when you check off — came from one prompt.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
        )
    }
}

private struct Habit: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    var doneToday: Bool
    var streakDays: Int

    static func starterSet() -> [Habit] {
        [
            Habit(title: "Morning walk",      icon: "figure.walk",       tint: .orange,    doneToday: true,  streakDays: 14),
            Habit(title: "Read 20 minutes",   icon: "book.fill",         tint: .pink,      doneToday: true,  streakDays: 9),
            Habit(title: "Stretch",           icon: "figure.cooldown",   tint: .yellow,    doneToday: false, streakDays: 3),
            Habit(title: "Glass of water",    icon: "drop.fill",         tint: .cyan,      doneToday: false, streakDays: 6),
            Habit(title: "Journal 3 lines",   icon: "pencil.line",       tint: .purple,    doneToday: false, streakDays: 11),
        ]
    }
}
