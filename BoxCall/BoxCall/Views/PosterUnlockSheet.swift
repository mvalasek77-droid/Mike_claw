import SwiftUI

/// Thirty-second flow to unlock real posters. TMDB keys are free and
/// instant; the app stores it in UserDefaults (overriding Info.plist)
/// and immediately re-fetches so the user watches posters bloom in.
struct PosterUnlockSheet: View {
    @EnvironmentObject var market: MarketService
    @Environment(\.dismiss) private var dismiss
    @State private var key: String = Config.tmdbAPIKeyOverride ?? ""
    @State private var testing = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    steps
                    keyField
                    if let error { Text(error).font(.caption).foregroundStyle(Theme.bear) }
                    if success {
                        Label("Posters unlocked. Pull down on Now Showing.", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.bull)
                    }
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            if testing { ProgressView().tint(.black) }
                            Text(testing ? "Checking…" : "Unlock real posters")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DepthButtonStyle())
                    .disabled(key.trimmingCharacters(in: .whitespaces).count < 20 || testing)
                    if Config.tmdbAPIKeyOverride != nil {
                        Button("Remove key") {
                            Config.tmdbAPIKeyOverride = nil
                            key = ""
                            success = false
                            market.provider = Config.compositeProvider
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("The key stays on this device only. We never send it anywhere except TMDB.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Real posters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarqueeBulbs(count: 12)
            Text("Turn the lights on.")
                .font(Theme.Type.marqueeH1)
                .foregroundStyle(Theme.cream)
            Text("BoxCall ships with the real slate — titles, dates, cast, directors. Add a free TMDB key and every movie gets its actual poster, plus live updates as new releases get dated.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Open themoviedb.org and create a free account.",
                 link: URL(string: "https://www.themoviedb.org/signup"))
            step(2, "Settings → API → Request an API key (choose Developer).",
                 link: URL(string: "https://www.themoviedb.org/settings/api"))
            step(3, "Copy the **API Key (v3 auth)** and paste it below.")
        }
        .padding(12)
        .glassSurface(radius: Theme.Radius.md, tint: Theme.marqueeGold)
    }

    private func step(_ n: Int, _ text: String, link: URL? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.marqueeGold))
            VStack(alignment: .leading, spacing: 2) {
                Text(.init(text)).font(.callout)
                if let link {
                    Link(link.host ?? link.absoluteString, destination: link)
                        .font(.caption).foregroundStyle(Theme.marqueeGold)
                }
            }
        }
    }

    private var keyField: some View {
        TextField("TMDB API key (v3)", text: $key)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Color(.secondarySystemBackground)))
    }

    @MainActor
    private func test() async {
        testing = true; error = nil; success = false
        defer { testing = false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = TMDBMovieProvider(apiKey: trimmed)
        do {
            let movies = try await provider.fetchUpcoming(windowDays: 90)
            guard !movies.isEmpty else { error = "Key works, but TMDB returned no upcoming movies. Try again in a minute."; return }
            Config.tmdbAPIKeyOverride = trimmed
            market.provider = Config.compositeProvider
            await market.refreshCatalog()
            success = true
            Haptics.won(large: true)
        } catch {
            self.error = "TMDB rejected that key. Double-check you copied the v3 key, not the Read Access Token."
            Haptics.warning()
        }
    }
}
