import SwiftUI

/// Home screen: "Just ramble." A big input box, an optional model override, and
/// the Coach It button. Detection + recommendation happen on submit.
struct RambleView: View {
    @EnvironmentObject private var app: AppState
    @State private var ramble = ""
    @State private var result: CoachResult?
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        editor
                        coachButton
                        if !app.history.isEmpty { recentStrip }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Prompt Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { HistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("History")
                }
            }
            .navigationDestination(item: $result) { ResultView(result: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Just ramble.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Glass.primaryText)
            Text("Dump whatever's in your head — half-formed, out of order, contradictory is fine. I'll turn it into a clean, model-ready Claude prompt and show you how.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Glass.primaryText.opacity(0.7))
        }
    }

    private var editor: some View {
        GlassCard {
            TextEditor(text: $ramble)
                .focused($editing)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Glass.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(12)
                .overlay(alignment: .topLeading) {
                    if ramble.isEmpty {
                        Text("e.g. \"need to reply to a customer mad about a late order, it shipped late cause of the carrier not us, be nice but don't just refund cash, offer store credit, keep it short\"")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Glass.primaryText.opacity(0.35))
                            .padding(.horizontal, 17).padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var coachButton: some View {
        Button {
            editing = false
            Haptics.success()
            let r = app.coach(ramble)
            app.save(r)
            withAnimation(Glass.motion) { result = r }
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Coach It").fontWeight(.semibold)
            }
            .font(.system(size: 17, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(colors: [Glass.accent, Glass.accentSecondary],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: Glass.cornerMedium, style: .continuous)
            )
        }
        .disabled(ramble.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
        .opacity(ramble.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 ? 0.5 : 1)
    }

    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent").font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Glass.primaryText.opacity(0.5)).textCase(.uppercase)
            ForEach(app.history.prefix(3)) { r in
                NavigationLink { ResultView(result: r) } label: {
                    HStack {
                        Text(r.ramble).lineLimit(1)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Glass.primaryText.opacity(0.85))
                        Spacer()
                        Text(app.pack.model(id: r.chosenModelID)?.name ?? r.chosenModelID)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Glass.tint(for: r.chosenModelID))
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}
