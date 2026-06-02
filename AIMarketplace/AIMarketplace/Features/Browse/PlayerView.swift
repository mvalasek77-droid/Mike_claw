import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// Dedicated consumption surface, adapting to the media type. Plays real
/// bundled/streamed media via AVFoundation when a file is resolved
/// (`ContentResolver`), and falls back to a polished simulated playhead so the
/// experience is complete even before assets are added.
struct PlayerView: View {
    let item: MediaItem
    /// Caller's intent to play a limited sample. Ownership ALWAYS wins — a
    /// buyer never sees a preview, even if the player was opened from a stale
    /// "Read a sample" tap and previewMode never got reset. See effectivePreview.
    var preview: Bool = false
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    private var effectivePreview: Bool { preview && !store.owns(item) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            switch item.type {
            case .movie: VideoSurface(item: item, preview: effectivePreview)
            case .music: AudioSurface(item: item, preview: effectivePreview)
            case .novel: ReaderSurface(item: item, preview: effectivePreview)
            }

            HStack(spacing: 8) {
                CircleIconButton(icon: "chevron.down") { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    if effectivePreview {
                        Text("PREVIEW")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }
}

struct CircleIconButton: View {
    let icon: String
    var action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .accessibilityLabel(Text(icon == "chevron.down" ? "Close" : icon))
    }
}

// MARK: - Video

private struct VideoSurface: View {
    let item: MediaItem
    var preview = false
    @StateObject private var model = AVPlaybackModel()
    @State private var resolved = false

    var body: some View {
        ZStack {
            if model.hasMedia {
                VideoPlayer(player: model.player)
                    .ignoresSafeArea()
                if !item.aiTools.isEmpty {
                    AICreditView(item: item, tint: item.type.accent, size: 11)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(20)
                }
                if model.previewEnded { PreviewEndedBanner(type: item.type) }
            } else if !item.screenplayScenes.isEmpty {
                // Scout-built film: no video bytes yet, but the screenplay
                // scenes are real. Render them as a readable reel with the
                // 30-min free preview enforced as a scene-count gate.
                ScreenplayReelSurface(item: item, preview: preview)
            } else {
                SimulatedTransport(item: item, icon: "film.fill",
                                   caption: preview ? "Free preview · first 30 min" : "Now playing · \(item.genre)",
                                   secondsTotal: preview ? PlayerPreview.movieFreeSeconds : Double(item.length) * 60)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // don't auto-lock while watching
            guard !resolved else { return }
            resolved = true
            model.load(url: ContentResolver.mediaURL(for: item),
                       previewLimit: preview ? PlayerPreview.movieFreeSeconds : nil)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.teardown()
        }
    }
}

enum PlayerPreview {
    static let clipSeconds: Double = 20          // music sample
    static let movieFreeSeconds: Double = 30 * 60 // films: 30 minutes free
    static let pages = 3
}

/// Overlay shown when a capped preview clip reaches its limit.
struct PreviewEndedBanner: View {
    let type: MediaType
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(.white)
            Text("Preview ended").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Buy this title to \(type.verb.lowercased()) it in full.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerL))
    }
}

// MARK: - Audio

private struct AudioSurface: View {
    let item: MediaItem
    var preview = false
    @StateObject private var model = AVPlaybackModel()
    @State private var resolved = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [item.type.accent.opacity(0.35), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                PosterArt(item: item, showsTitle: false)
                    .frame(width: 260, height: 260)
                    .shadow(color: item.type.accent.opacity(0.5), radius: 40, y: 20)
                VStack(spacing: 4) {
                    Text(item.title).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text(item.creator).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    AICreditView(item: item, tint: item.type.accent)
                }

                if model.previewEnded {
                    PreviewEndedBanner(type: item.type)
                } else if model.hasMedia {
                    PlaybackBar(progress: model.progress, total: model.previewLimit ?? model.duration,
                                onSeek: { model.seek(toFraction: $0) })
                        .padding(.horizontal, 30)
                    TransportControls(isPlaying: model.isPlaying,
                                      onBack: { model.skip(-15) },
                                      onToggle: { model.togglePlay() },
                                      onForward: { model.skip(15) })
                } else {
                    SimulatedTransportControls(secondsTotal: preview ? PlayerPreview.clipSeconds : 210)
                }
                if preview && !model.previewEnded {
                    Text("Preview · first \(Int(PlayerPreview.clipSeconds))s")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            // Music keeps playing when locked (audio background mode); we do NOT
            // disable the idle timer here so the phone can lock as usual.
            guard !resolved else { return }
            resolved = true
            model.load(url: ContentResolver.mediaURL(for: item),
                       previewLimit: preview ? PlayerPreview.clipSeconds : nil,
                       title: item.title, artist: item.creator,
                       artwork: ContentResolver.artworkImage(for: item))
        }
        .onDisappear { model.teardown() }
    }
}

// MARK: - Reader

private struct ReaderSurface: View {
    let item: MediaItem
    var preview = false
    @State private var page = 0
    @AppStorage("readerFontSize") private var fontSize: Double = 18

    private var pages: [String] {
        let all = ReaderContent.pages(for: item)
        guard preview else { return all }
        var sample = Array(all.prefix(PlayerPreview.pages))
        sample.append("— End of preview —\n\nBuy “\(item.title)” to keep reading.")
        return sample
    }

    var body: some View {
        ZStack {
            Color(red: 0.09, green: 0.08, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, text in
                        ScrollView {
                            Text(text)
                                .font(.system(size: fontSize, weight: .regular, design: .serif))
                                .foregroundStyle(Color(red: 0.92, green: 0.90, blue: 0.84))
                                .lineSpacing(8)
                                .padding(.horizontal, 26)
                                .padding(.top, 64)
                                .padding(.bottom, 60)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }   // don't auto-lock while reading
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("by \(item.creator)").font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                AICreditView(item: item, tint: item.type.accent, size: 11)
                Spacer()
            }
            ProgressView(value: Double(page + 1), total: Double(max(pages.count, 1)))
                .tint(item.type.accent)
            HStack {
                Button { Haptics.tap(); fontSize = max(14, fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    .accessibilityLabel("Decrease text size")
                Spacer()
                Text("Page \(page + 1) of \(pages.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .accessibilityLabel("Page \(page + 1) of \(pages.count)")
                Spacer()
                Button { Haptics.tap(); fontSize = min(28, fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel("Increase text size")
            }
            .foregroundStyle(.white.opacity(0.8))
            .font(.system(size: 18))
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
        .background(.black.opacity(0.3))
    }
}

/// Paginates a title's text — the real bundled manuscript when present,
/// otherwise a short generated preview.
private enum ReaderContent {
    static func pages(for item: MediaItem) -> [String] {
        if let manuscript = ContentResolver.bookText(for: item) {
            return paginateProse(manuscript, perPage: 1500)
        }
        let opening = "Chapter One\n\n\(item.synopsis)\n\n"
        let filler = "The morning arrived the way all difficult mornings do — quietly, and then all at once. \(item.creator) had imagined this a hundred times, but imagination, it turned out, was a poor rehearsal for the thing itself. "
        return paginateProse(opening + String(repeating: filler, count: 12), perPage: 520)
    }

    /// Splits on paragraph boundaries so chapter breaks and spacing survive.
    private static func paginateProse(_ text: String, perPage: Int) -> [String] {
        var pages: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if !current.isEmpty && current.count + paragraph.count + 1 > perPage {
                pages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
            current += paragraph + "\n"
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pages.append(tail) }
        return pages.isEmpty ? [text] : pages
    }
}

// MARK: - Shared transport

struct PlaybackBar: View {
    let progress: Double
    let total: Double
    var onSeek: (Double) -> Void

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                    Capsule().fill(.white).frame(width: max(0, geo.size.width * progress), height: 4)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        onSeek(min(1, max(0, value.location.x / geo.size.width)))
                    }
                )
            }
            .frame(height: 12)
            HStack {
                Text(timeString(progress * total)).font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Text("-" + timeString(max(0, (1 - progress) * total))).font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct TransportControls: View {
    let isPlaying: Bool
    var onBack: () -> Void
    var onToggle: () -> Void
    var onForward: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            Button { Haptics.tap(); onBack() } label: { Image(systemName: "gobackward.15").font(.system(size: 26, weight: .semibold)) }
                .accessibilityLabel("Skip back 15 seconds")
            Button { Haptics.tap(); onToggle() } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 70, weight: .bold))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            Button { Haptics.tap(); onForward() } label: { Image(systemName: "goforward.15").font(.system(size: 26, weight: .semibold)) }
                .accessibilityLabel("Skip forward 15 seconds")
        }
        .foregroundStyle(.white)
    }
}

/// Used when no real audio file is present yet.
private struct SimulatedTransportControls: View {
    let secondsTotal: Double
    @State private var playing = true
    @State private var progress: Double = 0.08
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            PlaybackBar(progress: progress, total: secondsTotal, onSeek: { progress = $0 })
                .padding(.horizontal, 30)
            TransportControls(isPlaying: playing,
                              onBack: { progress = max(0, progress - 0.05) },
                              onToggle: { playing.toggle(); Haptics.tap() },
                              onForward: { progress = min(1, progress + 0.05) })
            Text("Add your master to enable real playback")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            progress = min(1, progress + 1.0 / secondsTotal)
        }
    }
}

/// Full simulated surface for video when no film file is present.
private struct SimulatedTransport: View {
    let item: MediaItem
    let icon: String
    let caption: String
    let secondsTotal: Double

    var body: some View {
        ZStack {
            PosterArt(item: item, showsTitle: false)
                .blur(radius: 26)
                .overlay(Color.black.opacity(0.55))
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: icon).font(.system(size: 54, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                VStack(spacing: 4) {
                    Text(item.title).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("by \(item.creator)").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    AICreditView(item: item, tint: item.type.accent)
                }
                Text(caption).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                SimulatedTransportControls(secondsTotal: secondsTotal)
                    .padding(.bottom, 36).padding(.horizontal, 24)
            }
        }
    }
}

private func timeString(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// "Made with <AI>" credit; each AI is tappable and opens its Spotlight page.
struct AICreditView: View {
    let item: MediaItem
    var tint: Color = Theme.accent
    var size: CGFloat = 12
    @EnvironmentObject private var store: MarketplaceStore
    @State private var studio: AIStudio?

    var body: some View {
        if !item.aiTools.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "sparkles").font(.system(size: size - 1, weight: .semibold)).foregroundStyle(tint)
                Text("Made with").font(.system(size: size, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.65))
                ForEach(Array(item.aiTools.enumerated()), id: \.offset) { idx, tool in
                    if idx > 0 {
                        Text("·").font(.system(size: size)).foregroundStyle(.white.opacity(0.4))
                    }
                    Button { studio = store.studio(named: tool) } label: {
                        Text(tool).font(.system(size: size, weight: .heavy, design: .rounded))
                            .foregroundStyle(tint).underline()
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $studio) { AIStudioDetailView(studio: $0) }
        }
    }
}

/// Readable surface for Scout films that haven't been rendered to video yet.
/// Each scene is presented as a chapter. Free preview unlocks the first scenes
/// up to 30 min of accumulated runtime; the rest is gated behind purchase.
private struct ScreenplayReelSurface: View {
    let item: MediaItem
    var preview: Bool = false

    /// Scenes the buyer can read right now. In preview mode, accumulate scenes
    /// until total runtime crosses 30 min, then stop — the next scene is paywalled.
    private var unlockedScenes: [(idx: Int, text: String, minutes: Int)] {
        guard preview else {
            return zip(item.screenplayScenes.indices, item.screenplayScenes).map {
                (idx: $0.0, text: $0.1, minutes: item.sceneDurations[safe: $0.0] ?? 3)
            }
        }
        var out: [(idx: Int, text: String, minutes: Int)] = []
        var total = 0
        let freeMins = Int(PlayerPreview.movieFreeSeconds / 60)
        for (i, text) in item.screenplayScenes.enumerated() {
            let m = item.sceneDurations[safe: i] ?? 3
            if total + m > freeMins, !out.isEmpty { break }
            out.append((idx: i, text: text, minutes: m))
            total += m
        }
        return out
    }

    private var lockedCount: Int { max(0, item.screenplayScenes.count - unlockedScenes.count) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(unlockedScenes, id: \.idx) { scene in
                    sceneBlock(number: scene.idx + 1, text: scene.text, minutes: scene.minutes)
                }
                if preview && lockedCount > 0 {
                    paywall
                } else if item.isFilmInProgress {
                    inProgressFooter
                }
            }
            .padding(20)
        }
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.05, blue: 0.08), .black],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("\(item.genre) · Screenplay edition · \(item.totalSceneMinutes) min across \(item.screenplayScenes.count) scenes\(item.isFilmInProgress ? " (in progress)" : "")")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sceneBlock(number: Int, text: String, minutes: Int) -> some View {
        let videoURLString = item.sceneVideoURLs[safe: number - 1] ?? ""
        let videoURL = URL(string: videoURLString)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: videoURL != nil ? "play.rectangle.fill" : "doc.text.fill")
                    .font(.system(size: 12)).foregroundStyle(videoURL != nil ? Theme.success : Theme.kdp)
                Text("Scene \(number)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("· \(minutes) min")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                if videoURL != nil {
                    Text("VIDEO").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.success)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().stroke(Theme.success, lineWidth: 1))
                } else {
                    Text("SCREENPLAY").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.kdp)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().stroke(Theme.kdp, lineWidth: 1))
                }
            }
            if let url = videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .serif)).foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private var paywall: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(Theme.warning)
                Text("\(lockedCount) more scene\(lockedCount == 1 ? "" : "s") · \(item.totalSceneMinutes - unlockedScenes.reduce(0) { $0 + $1.minutes }) min remaining")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Spacer()
            }
            Text("You've watched the free 30 min. Buy the film to unlock the remaining scenes — and any new scenes the Scout adds as the film grows.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warning.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.warning.opacity(0.4), lineWidth: 0.6))
    }

    private var inProgressFooter: some View {
        let remaining = max(0, item.targetMinutes - item.totalSceneMinutes)
        return HStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text("Film still growing — \(remaining) min more queued. The Scout adds a new scene each cycle until the full \(item.targetMinutes)-minute cut lands. Buying now unlocks every scene as it ships.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(12)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
