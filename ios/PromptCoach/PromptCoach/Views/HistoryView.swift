import SwiftUI

/// On-device history of past coaching sessions. Searchable; tap to reopen.
struct HistoryView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""

    private var filtered: [CoachResult] {
        guard !query.isEmpty else { return app.history }
        return app.history.filter { $0.ramble.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            if app.history.isEmpty {
                ContentUnavailableView("No sessions yet",
                                       systemImage: "clock",
                                       description: Text("Coached prompts you create show up here."))
            } else {
                List {
                    ForEach(filtered) { r in
                        NavigationLink { ResultView(result: r) } label: { row(r) }
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { idx in idx.map { filtered[$0] }.forEach(app.delete) }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Search rambles")
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !app.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { app.clearHistory() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Clear history")
                }
            }
        }
    }

    private func row(_ r: CoachResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.ramble).lineLimit(2)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Glass.primaryText.opacity(0.9))
            HStack(spacing: 8) {
                Text(app.pack.model(id: r.chosenModelID)?.name ?? r.chosenModelID)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Glass.tint(for: r.chosenModelID))
                Text("· score \(r.reportCard.score)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Glass.primaryText.opacity(0.5))
                Spacer()
                Text(r.date, style: .date)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Glass.primaryText.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }
}
