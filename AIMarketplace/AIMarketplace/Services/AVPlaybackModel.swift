import SwiftUI
import AVFoundation
import Combine
import MediaPlayer

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
    /// When set, playback is a capped preview; it stops at this many seconds.
    @Published var previewLimit: Double?
    @Published private(set) var previewEnded = false

    let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var npTitle = ""
    private var npArtist = ""
    private var npArtwork: UIImage?
    private var remoteConfigured = false

    func configureSession() {
        #if !targetEnvironment(simulator)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    /// `title`/`artist` enable lock-screen Now Playing + remote controls so audio
    /// is controllable while the phone is locked.
    func load(url: URL?, previewLimit: Double? = nil, title: String? = nil, artist: String? = nil, artwork: UIImage? = nil) {
        guard let url else { hasMedia = false; return }
        self.previewLimit = previewLimit
        previewEnded = false
        configureSession()
        if let title {
            npTitle = title
            npArtist = artist ?? ""
            npArtwork = artwork
            configureRemoteCommands()
        }
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
            self.currentTime = seconds.isFinite ? seconds : 0
            // Preview cap: stop at the limit.
            if let limit = self.previewLimit, seconds.isFinite, seconds >= limit {
                self.pause()
                self.previewEnded = true
                self.progress = 1
                return
            }
            let denom = self.previewLimit ?? item.duration.seconds
            if denom.isFinite, denom > 0 {
                if self.previewLimit == nil { self.duration = denom }
                self.progress = min(1, max(0, seconds / denom))
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
        if previewEnded {
            player.seek(to: .zero)
            previewEnded = false
            progress = 0
        } else if progress >= 1 {
            seek(toFraction: 0)
        }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let target = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: target)
        progress = fraction
        updateNowPlaying()
    }

    func skip(_ seconds: Double) {
        guard duration > 0 else { return }
        seek(toFraction: min(1, max(0, (currentTime + seconds) / duration)))
    }

    // MARK: - Lock-screen Now Playing

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }; return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(15) }; return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-15) }; return .success
        }
        remoteConfigured = true
    }

    private func updateNowPlaying() {
        guard remoteConfigured else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: npTitle,
            MPMediaItemPropertyArtist: npArtist
        ]
        let total = previewLimit ?? duration
        if total > 0 { info[MPMediaItemPropertyPlaybackDuration] = total }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let art = npArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func teardown() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        if remoteConfigured {
            let center = MPRemoteCommandCenter.shared()
            center.playCommand.removeTarget(nil)
            center.pauseCommand.removeTarget(nil)
            center.togglePlayPauseCommand.removeTarget(nil)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            remoteConfigured = false
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
}
