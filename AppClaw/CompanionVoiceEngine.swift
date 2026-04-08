import Foundation
import AVFoundation
import SwiftUI

// MARK: - VoiceCharacter
//
// Describes an original on-device voice persona.
// 100% free — uses Apple's built-in Neural/Eloquence voices + AVAudioEngine
// post-processing to create distinct emotional characters. No API, no cost,
// works permanently with zero connectivity.
//
// Voice archetypes (emotional register, not celebrity copies):
//   Luna  → warm, breathy, intimate      (Hollywood-glamour register)
//   Aria  → bright, confident, crisp     (sharp modern-woman register)
//   Kel   → smooth, calm, measured       (therapeutic-presence register)
//   Marco → deep, direct, grounded       (quiet-strength register)
//   Dante → rich, resonant, passionate   (poetic-romantic register)
//   Kai   → clear, steady, minimal       (grounded-confidence register)

struct VoiceCharacter: Codable {

    // Ordered list of Apple voice bundle IDs to try; first available wins.
    let voiceIdentifiers: [String]
    let fallbackLanguage: String   // BCP-47, last resort

    // AVSpeechSynthesizer knobs
    let pitchMultiplier: Float     // 0.5–2.0  (1.0 = neutral)
    let rate: Float                // speech rate
    let preDelay: TimeInterval
    let postDelay: TimeInterval

    // AVAudioUnitTimePitch — applied after synthesis
    let timePitchRate: Double      // 0.5–2.0 (1.0 = unchanged)
    let timePitchCents: Float      // semitone shift × 100; e.g. -200 = -2 st

    // AVAudioUnitReverb — adds space / warmth
    let reverbPreset: Int          // AVAudioUnitReverbPreset.rawValue
    let reverbMix: Float           // 0–100 dry/wet

    // AVAudioUnitEQ — 3-band tonal shaping
    let eqLowShelfFreq: Float;  let eqLowShelfGain: Float
    let eqMidFreq: Float;       let eqMidGain: Float;   let eqMidBW: Float
    let eqHighShelfFreq: Float; let eqHighShelfGain: Float

    let characterName: String      // used for voice settings UI label
}

// MARK: - Preset characters

extension VoiceCharacter {

    // ────────────────────────────────────────────────────────────────
    // LUNA — warm, breathy, slow; like being spoken to very close up.
    // Eloquence Sandy (iOS 16+) → warmth | +1.5 st pitch | medium-room reverb
    // EQ: boost body, roll off harshness
    // ────────────────────────────────────────────────────────────────
    static let luna = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.eloquence.en-US.Sandy",      // iOS 16+ Eloquence, warm female
            "com.apple.voice.enhanced.en-US.Ava",   // Enhanced neural
            "com.apple.ttsbundle.Samantha-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 1.14,
        rate: 0.42,
        preDelay: 0.35, postDelay: 0.25,
        timePitchRate: 1.0, timePitchCents: +150,   // +1.5 st: luminous, lighter
        reverbPreset: AVAudioUnitReverbPreset.mediumRoom.rawValue, reverbMix: 20,
        eqLowShelfFreq: 220,  eqLowShelfGain: +2.0,
        eqMidFreq: 900,       eqMidGain: +1.5,   eqMidBW: 1.2,
        eqHighShelfFreq: 5500, eqHighShelfGain: -2.5,
        characterName: "Luna"
    )

    // ────────────────────────────────────────────────────────────────
    // ARIA — confident, present, no-fluff. Australian Karen voice
    // gives a non-generic distinctiveness. Small-room reverb = presence.
    // EQ: mid lift for cut-through; air shelf for brightness
    // ────────────────────────────────────────────────────────────────
    static let aria = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-AU.Karen", // Australian, distinctive, confident
            "com.apple.eloquence.en-US.Shelley",    // iOS 16+ Eloquence, energetic
            "com.apple.voice.enhanced.en-US.Nicky"
        ],
        fallbackLanguage: "en-AU",
        pitchMultiplier: 1.04,
        rate: 0.52,
        preDelay: 0.10, postDelay: 0.12,
        timePitchRate: 1.02, timePitchCents: +50,   // barely shifted; natural confidence
        reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: 8,
        eqLowShelfFreq: 140,  eqLowShelfGain: +0.5,
        eqMidFreq: 1400,      eqMidGain: +2.5,   eqMidBW: 0.9,
        eqHighShelfFreq: 7000, eqHighShelfGain: +1.5,
        characterName: "Aria"
    )

    // ────────────────────────────────────────────────────────────────
    // KEL — slowest, deepest reverb, most warmth. ASMR-adjacent calm.
    // British Kate has a measured, trustworthy quality.
    // EQ: heavy bass warmth, sharp-mid cut, high-shelf rolloff
    // ────────────────────────────────────────────────────────────────
    static let kel = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-GB.Kate",  // British calm, measured
            "com.apple.eloquence.en-US.Grandma",    // iOS 16+, gentle
            "com.apple.voice.enhanced.en-IE.Moira"  // Irish warmth
        ],
        fallbackLanguage: "en-GB",
        pitchMultiplier: 0.94,
        rate: 0.38,
        preDelay: 0.45, postDelay: 0.35,
        timePitchRate: 0.97, timePitchCents: -100,  // -1 st: grounded, anchoring
        reverbPreset: AVAudioUnitReverbPreset.largeChamber.rawValue, reverbMix: 28,
        eqLowShelfFreq: 280,  eqLowShelfGain: +3.0,
        eqMidFreq: 1800,      eqMidGain: -1.5,   eqMidBW: 1.0,
        eqHighShelfFreq: 4800, eqHighShelfGain: -3.5,
        characterName: "Kel"
    )

    // ────────────────────────────────────────────────────────────────
    // MARCO — deep, measured, no performance. Rocko (iOS 16+) is the
    // best built-in deep-male Eloquence voice. -2 st shift adds weight.
    // EQ: chest-voice boost, reduce boxy mid, smooth top
    // ────────────────────────────────────────────────────────────────
    static let marco = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.eloquence.en-US.Rocko",      // iOS 16+ deep male
            "com.apple.voice.enhanced.en-US.Evan",  // clear, direct
            "com.apple.ttsbundle.Alex-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.80,
        rate: 0.47,
        preDelay: 0.20, postDelay: 0.28,
        timePitchRate: 0.96, timePitchCents: -200,  // -2 st: distinct authority
        reverbPreset: AVAudioUnitReverbPreset.mediumHall.rawValue, reverbMix: 14,
        eqLowShelfFreq: 120,  eqLowShelfGain: +4.0,
        eqMidFreq: 800,       eqMidGain: -1.0,   eqMidBW: 1.1,
        eqHighShelfFreq: 6000, eqHighShelfGain: -2.0,
        characterName: "Marco"
    )

    // ────────────────────────────────────────────────────────────────
    // DANTE — rich, unhurried, resonant. Same base as Marco but with
    // more reverb warmth and heavy low-mid richness.
    // -1.5 st shift gives him a romantic, full-bodied resonance.
    // ────────────────────────────────────────────────────────────────
    static let dante = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-US.Alex",  // polished US male
            "com.apple.eloquence.en-US.Rocko",
            "com.apple.voice.enhanced.en-IE.Daniel" // Irish warmth fallback
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.88,
        rate: 0.42,
        preDelay: 0.38, postDelay: 0.30,
        timePitchRate: 0.95, timePitchCents: -150,  // -1.5 st: rich, resonant
        reverbPreset: AVAudioUnitReverbPreset.mediumRoom.rawValue, reverbMix: 24,
        eqLowShelfFreq: 200,  eqLowShelfGain: +3.5,
        eqMidFreq: 650,       eqMidGain: +2.0,   eqMidBW: 1.3,
        eqHighShelfFreq: 5000, eqHighShelfGain: -1.5,
        characterName: "Dante"
    )

    // ────────────────────────────────────────────────────────────────
    // KAI — minimal processing, present, clear. Small reverb = he's
    // just there, no embellishment. EQ is nearly flat with a touch of
    // mid presence and light bass foundation.
    // ────────────────────────────────────────────────────────────────
    static let kai = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-US.Evan",  // direct, grounded
            "com.apple.eloquence.en-US.Rocko",
            "com.apple.ttsbundle.Alex-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.85,
        rate: 0.50,
        preDelay: 0.15, postDelay: 0.18,
        timePitchRate: 1.0, timePitchCents: -100,   // -1 st: grounded, calm
        reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: 7,
        eqLowShelfFreq: 140,  eqLowShelfGain: +1.5,
        eqMidFreq: 1000,      eqMidGain: +1.0,   eqMidBW: 1.0,
        eqHighShelfFreq: 7000, eqHighShelfGain: +0.5,
        characterName: "Kai"
    )
}

// MARK: - CompanionVoiceEngine
//
// 100% on-device. No APIs. No recurring cost. Works offline permanently.
//
// Processing chain:
//   AVSpeechSynthesizer.write() → PCM buffers
//     → AVAudioPlayerNode
//     → AVAudioUnitTimePitch   (pitch shift + rate)
//     → AVAudioUnitEQ          (3-band tonal shaping)
//     → AVAudioUnitReverb      (space / warmth / character)
//     → mainMixerNode → speakers

@MainActor
final class CompanionVoiceEngine: NSObject, ObservableObject {

    static let shared = CompanionVoiceEngine()

    @Published var isSpeaking:   Bool = false
    @Published var voiceEnabled: Bool = UserDefaults.standard.bool(forKey: "companion.voiceEnabled")

    // MARK: - Audio graph nodes

    private let engine     = AVAudioEngine()
    private let player     = AVAudioPlayerNode()
    private let pitchUnit  = AVAudioUnitTimePitch()
    private let eqUnit     = AVAudioUnitEQ(numberOfBands: 3)
    private let reverbUnit = AVAudioUnitReverb()

    // MARK: - Synthesizer

    private let synth = AVSpeechSynthesizer()
    private var engineReady = false

    private override init() {
        super.init()
        synth.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Public speak

    func speak(_ text: String, character: VoiceCharacter) {
        guard voiceEnabled else { return }
        stopSpeaking()

        let clean = stripMarkdown(text)
        guard !clean.isEmpty else { return }

        isSpeaking = true
        startEngine(character: character)

        guard engineReady else { return }

        let utterance = buildUtterance(clean, character: character)

        // Capture node refs before entering the synth callback.
        // AVAudioPlayerNode.scheduleBuffer() is thread-safe — calling it
        // directly from the synth callback avoids the main-thread round-trip
        // that was causing buffers to arrive late and voice to cut out.
        let capturedPlayer = player
        let capturedEngine = engine

        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer,
                  pcm.frameLength > 0,
                  capturedEngine.isRunning else { return }
            capturedPlayer.scheduleBuffer(pcm)
        }
    }

    func speakWithCurrentCompanion(_ text: String) {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let c  = CompanionPersonality.find(id: id) ?? .luna
        speak(text, character: c.voiceCharacter)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        if player.isPlaying   { player.stop() }
        if engine.isRunning   { engine.stop() }
        engine.reset()
        engineReady = false
        isSpeaking  = false
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: "companion.voiceEnabled")
        if !voiceEnabled { stopSpeaking() }
    }

    // MARK: - Engine setup

    private func startEngine(character: VoiceCharacter) {
        if engine.isRunning { engine.stop() }
        engine.reset()   // detaches all nodes cleanly before re-attaching

        engine.attach(player)
        engine.attach(pitchUnit)
        engine.attach(eqUnit)
        engine.attach(reverbUnit)

        // Apply character settings
        pitchUnit.rate  = Float(character.timePitchRate)
        pitchUnit.pitch = character.timePitchCents

        applyEQ(character)

        if let preset = AVAudioUnitReverbPreset(rawValue: character.reverbPreset) {
            reverbUnit.loadFactoryPreset(preset)
        }
        reverbUnit.wetDryMix = character.reverbMix

        // Use a standard mono format at 22050 Hz (matches synth output)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 22050, channels: 1, interleaved: false)

        engine.connect(player,     to: pitchUnit,           format: fmt)
        engine.connect(pitchUnit,  to: eqUnit,              format: fmt)
        engine.connect(eqUnit,     to: reverbUnit,          format: fmt)
        engine.connect(reverbUnit, to: engine.mainMixerNode, format: fmt)

        do {
            try engine.start()
            player.play()
            engineReady = true
        } catch {
            // Engine failed to start — synth will still play unprocessed
            engineReady = false
        }
    }

    private func applyEQ(_ c: VoiceCharacter) {
        guard eqUnit.bands.count >= 3 else { return }

        eqUnit.bands[0].filterType = .lowShelf
        eqUnit.bands[0].frequency  = c.eqLowShelfFreq
        eqUnit.bands[0].gain       = c.eqLowShelfGain
        eqUnit.bands[0].bypass     = false

        eqUnit.bands[1].filterType = .parametric
        eqUnit.bands[1].frequency  = c.eqMidFreq
        eqUnit.bands[1].gain       = c.eqMidGain
        eqUnit.bands[1].bandwidth  = c.eqMidBW
        eqUnit.bands[1].bypass     = false

        eqUnit.bands[2].filterType = .highShelf
        eqUnit.bands[2].frequency  = c.eqHighShelfFreq
        eqUnit.bands[2].gain       = c.eqHighShelfGain
        eqUnit.bands[2].bypass     = false
    }

    private func buildUtterance(_ text: String, character: VoiceCharacter) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = bestVoice(character)
        u.pitchMultiplier   = max(0.5, min(2.0, character.pitchMultiplier))
        u.rate              = max(AVSpeechUtteranceMinimumSpeechRate,
                                  min(AVSpeechUtteranceMaximumSpeechRate, character.rate))
        u.preUtteranceDelay  = character.preDelay
        u.postUtteranceDelay = character.postDelay
        return u
    }

    private func bestVoice(_ character: VoiceCharacter) -> AVSpeechSynthesisVoice? {
        // Try Eloquence / Enhanced voices first (better quality, iOS 16+)
        for id in character.voiceIdentifiers {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }
        return AVSpeechSynthesisVoice(language: character.fallbackLanguage)
    }

    // MARK: - Markdown stripper

    private func stripMarkdown(_ s: String) -> String {
        var t = s
        for token in ["**", "__", "*", "_", "`", "# ", "## "] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension CompanionVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Let the engine drain its buffer ring before marking done
            try? await Task.sleep(nanoseconds: 400_000_000)
            isSpeaking  = false
            engineReady = false
            if engine.isRunning { engine.stop() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking  = false
            engineReady = false
        }
    }
}

// MARK: - CompanionVoiceSpeakButton

struct CompanionVoiceSpeakButton: View {
    let message: String
    @ObservedObject private var engine = CompanionVoiceEngine.shared

    var body: some View {
        Button {
            if engine.isSpeaking {
                engine.stopSpeaking()
            } else {
                engine.speakWithCurrentCompanion(message)
            }
        } label: {
            Image(systemName: engine.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.1")
                .font(.system(size: 12))
                .foregroundColor(engine.isSpeaking ? .OC.accent : .OC.textMuted)
                .symbolEffect(.variableColor, isActive: engine.isSpeaking)
                .padding(6)
                .background(Color.OC.surface)
                .cornerRadius(8)
        }
    }
}
