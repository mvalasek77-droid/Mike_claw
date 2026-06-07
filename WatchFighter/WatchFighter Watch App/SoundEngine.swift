#if os(watchOS)
import AVFoundation

/// Asset-free SFX: short enveloped tones synthesised at startup and played via
/// AVAudioEngine. No bundled audio files needed, so the prototype makes noise
/// out of the box; swap in real samples in M3 by replacing `buffer(for:)`.
final class SoundEngine {
    static let shared = SoundEngine()

    enum SFX {
        case light, heavy, special, block, parry, hit, ko, ready, menu
    }

    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private var rr = 0                                   // round-robin voice
    private let format: AVAudioFormat
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var started = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        players = (0..<6).map { _ in AVAudioPlayerNode() }
        players.forEach { engine.attach($0); engine.connect($0, to: engine.mainMixerNode, format: format) }
    }

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            started = false       // stay silent rather than crash
        }
    }

    func play(_ sfx: SFX) {
        guard started, let buf = buffer(for: sfx) else { return }
        let node = players[rr]; rr = (rr + 1) % players.count
        node.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    /// Map a combat event to a sound (only the local viewer's perspective).
    func play(for event: CombatEvent, viewer: Side) {
        switch event {
        case .hitLanded(let a, _): play(a == viewer ? .hit : .hit)
        case .blocked:             play(.block)
        case .parried:             play(.parry)
        case .heavyWindup:         play(.heavy)
        case .specialReady:        play(.ready)
        case .knockdown, .roundOver: play(.ko)
        default: break
        }
    }

    // MARK: - Tone synthesis

    private func buffer(for sfx: SFX) -> AVAudioPCMBuffer? {
        let key = "\(sfx)"
        if let cached = cache[key] { return cached }
        let spec: (freq: Double, dur: Double, square: Bool, sweep: Double)
        switch sfx {
        case .light:   spec = (660, 0.06, true,  0)
        case .heavy:   spec = (180, 0.12, true,  -40)
        case .special: spec = (440, 0.22, false, 220)
        case .block:   spec = (120, 0.07, true,  0)
        case .parry:   spec = (900, 0.08, false, 300)
        case .hit:     spec = (240, 0.10, true,  -80)
        case .ko:      spec = (90,  0.45, true,  -30)
        case .ready:   spec = (520, 0.18, false, 180)
        case .menu:    spec = (700, 0.05, false, 0)
        }
        let buf = tone(freq: spec.freq, dur: spec.dur, square: spec.square, sweep: spec.sweep)
        cache[key] = buf
        return buf
    }

    private func tone(freq: Double, dur: Double, square: Bool, sweep: Double) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let n = AVAudioFrameCount(sr * dur)
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return nil }
        buf.frameLength = n
        guard let ch = buf.floatChannelData?[0] else { return nil }
        var phase = 0.0
        for i in 0..<Int(n) {
            let t = Double(i) / sr
            let f = freq + sweep * (t / dur)            // linear frequency sweep
            phase += 2 * Double.pi * f / sr
            var s = sin(phase)
            if square { s = s >= 0 ? 1 : -1 }
            // Quick attack, exponential decay envelope.
            let env = exp(-5.0 * t / dur) * min(1, t / 0.005)
            ch[i] = Float(s * env * 0.25)
        }
        return buf
    }
}
#endif
