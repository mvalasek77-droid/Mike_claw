import SwiftUI

/// First-launch announcement of the marketplace's inaugural roundtable. Shown
/// once per device — dismissed-state persists via UserDefaults so users
/// aren't nagged. Guarded by `shouldPresent(...)` to only appear AFTER the
/// MP3 has actually been bundled (no point announcing an episode that won't
/// play). The catalog entry itself is unconditional and stays the home-screen
/// hero regardless of whether this sheet has been seen.
struct InauguralLaunchSheet: View {
    let item: MediaItem
    var onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// UUID of the inaugural roundtable entry in SampleData.
    static let inauguralID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private static let seenKey = "aimkt.seenInauguralRoundtable.v1"

    /// Looks the item up + checks the file is actually bundled + checks the
    /// user hasn't already dismissed the sheet. Returns the item to present,
    /// or nil if any condition isn't met.
    static func itemIfReady(in catalog: [MediaItem]) -> MediaItem? {
        guard !UserDefaults.standard.bool(forKey: seenKey),
              let item = catalog.first(where: { $0.id == inauguralID }),
              ContentResolver.mediaURL(for: item) != nil
        else { return nil }
        return item
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    var body: some View {
        ZStack {
            // Premium dark backdrop with subtle gradient bloom.
            LinearGradient(colors: [Color(red: 0.05, green: 0.04, blue: 0.08),
                                    Color(red: 0.10, green: 0.06, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.18), .clear],
                           center: .top, startRadius: 30, endRadius: 500)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    badge
                    artwork
                    titleBlock
                    panelistRow
                    playButton
                    note
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 30)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
        .overlay(alignment: .topTrailing) {
            Button {
                Self.markSeen()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(14)
            }
            .accessibilityLabel("Dismiss")
        }
    }

    private var badge: some View {
        Text("PREMIERE EPISODE")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().stroke(Theme.accent, lineWidth: 1))
    }

    private var artwork: some View {
        ZStack {
            PosterArt(item: item, showsTitle: false)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.25), radius: 22, y: 8)
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 8)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text(item.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Four frontier models. One roundtable. The future of AI media.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    /// Four chips, one per panelist. A subtle but unmistakable "you're going
    /// to hear from these four" signal.
    private var panelistRow: some View {
        let panelists = [
            ("Claude Opus 4.8", "Anthropic"),
            ("GPT-5.5", "OpenAI"),
            ("Gemini", "Google DeepMind"),
            ("Grok", "xAI"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(panelists, id: \.0) { name, lab in
                VStack(spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(lab)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var playButton: some View {
        Button {
            Self.markSeen()
            onPlay()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .heavy))
                Text("Listen now").font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var note: some View {
        Text("Each panelist's words are generated by that model's own API; voices are rendered via studio TTS — none of these labs ship native audio you can route through a podcast pipeline today.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
