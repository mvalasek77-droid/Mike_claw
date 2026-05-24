import SwiftUI
import Combine
import Foundation

/// A self-contained mock consumption surface that adapts to the media type:
/// a video player for films, an audio player for music, and a reader for novels.
struct PlayerView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch item.type {
            case .movie: VideoPlayerSurface(item: item)
            case .music: AudioPlayerSurface(item: item)
            case .novel: ReaderSurface(item: item)
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                    Spacer()
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Video

private struct VideoPlayerSurface: View {
    let item: MediaItem
    @State private var playing = true
    @State private var progress: Double = 0.06

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PosterArt(item: item, showsTitle: false)
                .blur(radius: 26)
                .overlay(Color.black.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "film.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Now playing · \(item.genre)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                controls
            }
            .padding(.bottom, 36)
            .padding(.horizontal, 24)
        }
        .onReceive(timer) { _ in
            guard playing else { return }
            progress = min(1, progress + 1.0 / Double(max(item.length, 1) * 60))
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Scrubber(progress: $progress, total: Double(item.length) * 60)
            HStack(spacing: 40) {
                ctlButton("gobackward.10") { progress = max(0, progress - 0.02) }
                Button { playing.toggle(); Haptics.tap() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 68, height: 68)
                        .background(Circle().fill(.white))
                }
                ctlButton("goforward.10") { progress = min(1, progress + 0.02) }
            }
        }
    }

    private func ctlButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Audio

private struct AudioPlayerSurface: View {
    let item: MediaItem
    @State private var playing = true
    @State private var progress: Double = 0.1
    @State private var track = 1
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            PosterArt(item: item, showsTitle: false)
                .frame(width: 260, height: 260)
                .shadow(color: item.type.accent.opacity(0.5), radius: 40, y: 20)
            VStack(spacing: 4) {
                Text("Track \(track) of \(item.length)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Text(item.title).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(item.creator).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Scrubber(progress: $progress, total: 210)
                .padding(.horizontal, 30)
            HStack(spacing: 40) {
                ctl("backward.fill") { track = max(1, track - 1); progress = 0 }
                Button { playing.toggle(); Haptics.tap() } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70, weight: .bold)).foregroundStyle(.white)
                }
                ctl("forward.fill") { track = min(item.length, track + 1); progress = 0 }
            }
            Spacer()
        }
        .padding(24)
        .onReceive(timer) { _ in
            guard playing else { return }
            progress += 1.0 / 210
            if progress >= 1 { progress = 0; track = min(item.length, track + 1) }
        }
    }

    private func ctl(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Reader

private struct ReaderSurface: View {
    let item: MediaItem
    @State private var page = 1

    private var sample: String {
        """
        Chapter One

        \(item.synopsis)

        The morning arrived the way all difficult mornings do — quietly, and then all at once. \(item.creator) had imagined this scene a hundred times, but imagination, it turned out, was a poor rehearsal for the thing itself.

        There was a sound from the next room. Then silence. Then the sound again, patient as a clock, and twice as certain that it had somewhere to be.
        """
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(sample)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.92, green: 0.90, blue: 0.84))
                    .lineSpacing(8)
                    .padding(.horizontal, 26)
                    .padding(.top, 70)
                    .padding(.bottom, 40)
            }
            HStack {
                Button { page = max(1, page - 1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("Page \(page) of \(item.length)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { page = min(item.length, page + 1) } label: { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 30).padding(.vertical, 16)
        }
        .background(Color(red: 0.09, green: 0.08, blue: 0.07).ignoresSafeArea())
    }
}

// MARK: - Shared scrubber

private struct Scrubber: View {
    @Binding var progress: Double
    var total: Double

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22)).frame(height: 4)
                    Capsule().fill(.white).frame(width: max(0, geo.size.width * progress), height: 4)
                }
            }
            .frame(height: 8)
            HStack {
                Text(timeString(progress * total)).font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Text("-" + timeString((1 - progress) * total)).font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
