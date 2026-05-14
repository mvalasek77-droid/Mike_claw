import SwiftUI

/// Searchable memory of prior swarm decisions. This turns the raw
/// reasoning trail into an operator tool: users can answer "why did
/// CodeGenie choose this architecture?" without opening transcripts.
struct DecisionSearchView: View {
    @State private var query = ""
    @State private var results: [DecisionSearchRecord] = []
    @State private var loading = false
    @State private var error: String?
    private let client = SwarmClient()

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    searchBox
                    if let error { errorCard(error) }
                    if loading { loadingCard }
                    if !query.isEmpty && !loading && results.isEmpty && error == nil { emptyCard }
                    ForEach(results) { result in
                        DecisionResultCard(result: result)
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: query) { await searchAfterDelay() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Decision memory")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Swarm reasoning ledger across every build.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.58))
                .accessibilityHidden(true)
            TextField("Search decisions", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = ""; results = []; error = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Searching memory...")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
            }
            .padding(14)
        }
    }

    private var emptyCard: some View {
        GlassCard(title: "No matches", icon: "brain.head.profile", tint: LiquidGlass.accentSecondary) {
            Text("No remembered decision matched this query.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Search failed", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func searchAfterDelay() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            error = nil
            loading = false
            return
        }
        loading = true
        error = nil
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard !Task.isCancelled else { return }
        do {
            results = try await client.searchDecisions(query: trimmed, limit: 40)
        } catch {
            self.error = "\(error)"
            results = []
        }
        loading = false
    }
}

private struct DecisionResultCard: View {
    let result: DecisionSearchRecord

    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(LiquidGlass.accent)
                        .accessibilityHidden(true)
                    Text(result.context)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .textCase(.uppercase)
                    Spacer()
                    Text(result.at, format: .relative(presentation: .named))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(result.decision)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.jobID)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.context): \(result.decision)")
    }
}
