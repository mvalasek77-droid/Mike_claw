import SwiftUI
import AVFoundation
import Combine

/// Drives real audio/video playback via `AVPlayer`, exposing observable
/// transport state for SwiftUI. Used by both the audio and video surfaces.
/// When no playable URL is available the model stays idle and the views fall
/// back to a simulated playhead.
@MainActor
final class AVPlaybackModel: ObservableObject {
    @Published private(set) var hasMedia = false
    @Published var isPlaying = false
    @Published var progress: Double = 0      // 0…1
    @Published var currentTime: Double = 0    // seconds
    @Published var duration: Double = 0       // seconds

    let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func configureSession() {
        #if !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func load(url: URL?) {
        guard let url else { hasMedia = false; return }
        configureSession()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        hasMedia = true
        addObservers(for: item)
        play()
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            let total = item.duration.seconds
            self.currentTime = seconds.isFinite ? seconds : 0
            if total.isFinite, total > 0 {
                self.duration = total
                self.progress = min(1, max(0, seconds / total))
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 1
            }
        }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard hasMedia else { return }
        if progress >= 1 { seek(toFraction: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let target = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: target)
        progress = fraction
    }

    func skip(_ seconds: Double) {
        guard duration > 0 else { return }
        seek(toFraction: min(1, max(0, (currentTime + seconds) / duration)))
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
