import SwiftUI

/// A cinema-screen link to the movie's official-trailer search.
/// YouTube blocks its search-playlist player in many embedded views,
/// so opening the result directly avoids an empty error screen.
struct TrailerEmbed: View {
    let query: String

    private var trailerURL: URL {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }

    var body: some View {
        Link(destination: trailerURL) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.stageBlack, Theme.velvetRed.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                VStack(spacing: 9) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Theme.marqueeGold)
                    Text("WATCH THE OFFICIAL TRAILER")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Theme.cream)
                    Text("OPENS YOUTUBE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.marqueeGold.opacity(0.75))
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(16/9, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel("Watch trailer")
        .accessibilityHint("Opens YouTube search for \(query)")
    }
}
