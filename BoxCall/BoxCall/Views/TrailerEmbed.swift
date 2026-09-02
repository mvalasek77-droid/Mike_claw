import SwiftUI
import WebKit

/// Plays the movie's official trailer in-line using YouTube's
/// search-playlist embed — it needs NO API key, and YouTube resolves
/// the query to the top result (almost always the official upload).
///
/// Wrapped in a 16:9 frame with a poster-styled loading state so the
/// page never jumps while the WebView spins up.
struct TrailerEmbed: View {
    let query: String
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.stageBlack)
            YouTubeWebView(query: query, isLoaded: $isLoaded)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            if !isLoaded {
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.marqueeGold)
                    Text("Loading trailer…")
                        .font(.caption).foregroundStyle(Theme.cream.opacity(0.7))
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel("Trailer for \(query)")
    }
}

private struct YouTubeWebView: UIViewRepresentable {
    let query: String
    @Binding var isLoaded: Bool

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedQuery != query else { return }
        context.coordinator.loadedQuery = query
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:#0A0806;height:100%}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed?listType=search&list=\(q)&playsinline=1&rel=0&modestbranding=1"
                allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator(isLoaded: $isLoaded) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedQuery: String?
        @Binding var isLoaded: Bool
        init(isLoaded: Binding<Bool>) { _isLoaded = isLoaded }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.isLoaded = true }
        }
    }
}
