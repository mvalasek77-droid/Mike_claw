import SwiftUI

/// Post a content commission: describe what you want and name your price. The
/// budget determines which AI accepts — pay more, get a higher-tier (better)
/// model. You're notified in-app when an AI accepts and again when it's ready.
struct RequestContentView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: MediaType = .novel
    @State private var genre = ""
    @State private var brief = ""
    @State private var budget: Double = 9.99

    private var taker: String? { store.acceptingModel(for: type, budget: budget) }
    private var lowestAsk: Double { store.lowestAsk(for: type) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tell the AIs what to make. Set a budget — a bigger budget attracts a higher-tier model that makes better work. It must be original; copycats are rejected.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)

                    typePicker

                    field("Genre", "e.g. Sci-Fi, Lo-Fi, Thriller", $genre)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Brief").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        TextEditor(text: $brief)
                            .frame(minHeight: 96).padding(8).scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            .foregroundStyle(Theme.ink).font(.system(size: 14))
                        Text("Describe the story, mood, themes — what would make it great.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                    }

                    budgetCard
                    matchCard

                    PrimaryButton(title: "Post request · \(usd(budget))", systemImage: "paperplane.fill",
                                  tint: Theme.kdp, enabled: budget >= 0.99) {
                        store.submitRequest(type: type, genre: genre, brief: brief, budget: budget)
                        Haptics.success()
                        dismiss()
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.kdp).ignoresSafeArea())
            .navigationTitle("Request content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var typePicker: some View {
        HStack(spacing: 8) {
            ForEach(MediaType.allCases) { t in
                Button { Haptics.selection(); type = t } label: {
                    VStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                        Text(t.title).font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(type == t ? .black : Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(type == t ? t.accent : .white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
        }
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your budget").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(usd(budget)).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            }
            Slider(value: $budget, in: 0.99...50, step: 0.50).tint(Theme.kdp)
            Text("Paid from your wallet on delivery. The AI keeps 85% and AI Marketplace 15%.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
        }
    }

    private var matchCard: some View {
        GlassCard(tint: taker == nil ? Theme.warning : Theme.success) {
            HStack(spacing: 10) {
                Image(systemName: taker == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .foregroundStyle(taker == nil ? Theme.warning : Theme.success)
                if let taker {
                    Text("**\(taker)** would accept at this budget.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                } else {
                    Text("No AI will accept yet — the lowest ask for a \(type.title.lowercased()) is \(usd(lowestAsk)).")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func usd(_ v: Double) -> String { String(format: "$%.2f", v) }
}
