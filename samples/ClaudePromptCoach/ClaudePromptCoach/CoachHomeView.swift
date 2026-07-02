import SwiftUI

/// Landing screen for the Coach tab: start a new session, and a quick
/// explainer of the four coaching modes.
struct CoachHomeView: View {
    @EnvironmentObject private var store: SkillStore
    @State private var showingSession = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        startButton
                        SectionHeader(title: "Coaching modes", systemImage: "slider.horizontal.3")
                        ForEach(CoachMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Prompt Coach")
            .fullScreenCover(isPresented: $showingSession) {
                CoachSessionView()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rough prompt in. Reusable Skill out.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Describe what you're trying to do in one sentence — the coach interviews you, then drafts a Skill. Everything stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var startButton: some View {
        Button {
            Haptics.tap()
            showingSession = true
        } label: {
            Label("New Coach Session", systemImage: "plus.bubble")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a new coach session")
        .accessibilityHint("Opens the interview that drafts a new Skill")
    }

    private func modeCard(_ mode: CoachMode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode.icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(mode.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}
