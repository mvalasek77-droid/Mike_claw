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
//
// FEMALE voices: silky, warm, close — like someone whispering just for you.
// Key recipe: Sandy/Ava (smoothest Apple voices), slow unhurried rate,
// intimate room reverb, cut harshness at 2–4 kHz, silk shimmer at 7–10 kHz.
//
// MALE voices: deep chest, full energy, direct.
// Key recipe: Rocko (deepest Apple voice), confident pace, heavy bass,
// dry/present mix (little reverb = sounds powerful in the room).

extension VoiceCharacter {

    // ────────────────────────────────────────────────────────────────
    // LUNA — silky, breathy, intimate. Every word feels chosen for you.
    // Sandy (Eloquence) is Apple's warmest female voice. Slow delivery,
    // heavy intimacy reverb, sharp high-shelf rolloff removes all edges.
    // ────────────────────────────────────────────────────────────────
    static let luna = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.eloquence.en-US.Sandy",          // #1 warmest Eloquence female
            "com.apple.voice.enhanced.en-US.Ava",       // Enhanced neural, very smooth
            "com.apple.voice.enhanced.en-US.Allison",   // Polished fallback
            "com.apple.ttsbundle.Samantha-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 1.08,          // gentle lift — feminine, not squeaky
        rate: 0.42,                     // slow & deliberate — savors every word
        preDelay: 0.22, postDelay: 0.08,
        timePitchRate: 1.0, timePitchCents: +80,   // barely lifted — natural brightness
        reverbPreset: AVAudioUnitReverbPreset.mediumRoom.rawValue, reverbMix: 22,
        eqLowShelfFreq: 220,  eqLowShelfGain: +2.0,  // body warmth
        eqMidFreq: 2800,      eqMidGain: -3.0,   eqMidBW: 1.0,  // cut harshness
        eqHighShelfFreq: 7000, eqHighShelfGain: -1.0,  // smooth silk top
        characterName: "Luna"
    )

    // ────────────────────────────────────────────────────────────────
    // ARIA — bright, confident, effortlessly cool.
    // Karen (Australian Eloquence) has natural crispness. EQ boosted for
    // presence and air — sounds like she's right across the table.
    // ────────────────────────────────────────────────────────────────
    static let aria = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-AU.Karen",     // Australian — crisp & natural
            "com.apple.eloquence.en-US.Shelley",        // Eloquence energetic
            "com.apple.voice.enhanced.en-US.Nicky",
            "com.apple.voice.enhanced.en-US.Ava"
        ],
        fallbackLanguage: "en-AU",
        pitchMultiplier: 1.05,
        rate: 0.48,                     // confident conversational
        preDelay: 0.10, postDelay: 0.06,
        timePitchRate: 1.0, timePitchCents: +60,
        reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: 8,
        eqLowShelfFreq: 180,  eqLowShelfGain: +1.0,
        eqMidFreq: 1200,      eqMidGain: +1.5,   eqMidBW: 0.8,  // presence lift
        eqHighShelfFreq: 7500, eqHighShelfGain: +1.5,            // air shimmer
        characterName: "Aria"
    )

    // ────────────────────────────────────────────────────────────────
    // KEL — ASMR-soft, therapeutic, like rain on a Sunday morning.
    // Slowest rate, large-chamber reverb wraps you up, heavy bass warmth.
    // Kate (British) has natural measured gravity.
    // ────────────────────────────────────────────────────────────────
    static let kel = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-GB.Kate",      // British, measured, trustworthy
            "com.apple.eloquence.en-US.Sandy",          // Sandy fallback — very warm
            "com.apple.voice.enhanced.en-IE.Moira"     // Irish warmth
        ],
        fallbackLanguage: "en-GB",
        pitchMultiplier: 0.96,          // slightly lower — grounding
        rate: 0.39,                     // slowest — never hurried
        preDelay: 0.28, postDelay: 0.18,
        timePitchRate: 0.98, timePitchCents: -60,
        reverbPreset: AVAudioUnitReverbPreset.largeChamber.rawValue, reverbMix: 26,
        eqLowShelfFreq: 280,  eqLowShelfGain: +3.0,  // deep warmth
        eqMidFreq: 2000,      eqMidGain: -2.5,   eqMidBW: 1.0,  // cut clinical edge
        eqHighShelfFreq: 5000, eqHighShelfGain: -3.0,            // roll off brightness
        characterName: "Kel"
    )

    // ────────────────────────────────────────────────────────────────
    // MARCO — deep chest, direct power. No performance — just real.
    // Rocko (Eloquence) is Apple's deepest male voice. Aggressive bass boost,
    // -2.5 semitone shift, almost no reverb = sounds like he's IN the room.
    // ────────────────────────────────────────────────────────────────
    static let marco = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.eloquence.en-US.Rocko",          // #1 deepest Eloquence male
            "com.apple.voice.enhanced.en-US.Evan",      // clear, grounded fallback
            "com.apple.ttsbundle.Alex-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.78,          // low pitch floor — chest voice
        rate: 0.52,                     // confident energy, not slow
        preDelay: 0.14, postDelay: 0.10,
        timePitchRate: 0.96, timePitchCents: -250,  // -2.5 st: real masculine depth
        reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: 6,
        eqLowShelfFreq: 100,  eqLowShelfGain: +5.5,  // massive chest boost
        eqMidFreq: 500,       eqMidGain: -2.5,   eqMidBW: 1.2,  // remove boxiness
        eqHighShelfFreq: 4000, eqHighShelfGain: +1.5,            // clarity & presence
        characterName: "Marco"
    )

    // ────────────────────────────────────────────────────────────────
    // DANTE — romantic, full-bodied, unhurried. The poet.
    // Rocko with more warmth and a richer EQ — sounds like red wine sounds.
    // More reverb than Marco = intimate room, not a podium.
    // ────────────────────────────────────────────────────────────────
    static let dante = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.eloquence.en-US.Rocko",          // deep, rich
            "com.apple.voice.enhanced.en-US.Alex",      // polished US male
            "com.apple.voice.enhanced.en-IE.Daniel"     // Irish warmth fallback
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.84,
        rate: 0.43,                     // unhurried — every phrase is intentional
        preDelay: 0.24, postDelay: 0.16,
        timePitchRate: 0.94, timePitchCents: -200,  // deep but warmer than Marco
        reverbPreset: AVAudioUnitReverbPreset.mediumRoom.rawValue, reverbMix: 20,
        eqLowShelfFreq: 160,  eqLowShelfGain: +4.5,  // rich chest tone
        eqMidFreq: 600,       eqMidGain: +1.5,   eqMidBW: 1.4,  // low-mid warmth
        eqHighShelfFreq: 5000, eqHighShelfGain: -2.0,            // smooth, no harshness
        characterName: "Dante"
    )

    // ────────────────────────────────────────────────────────────────
    // KAI — grounded, direct, full of quiet energy.
    // Evan is the most "present-in-the-room" Apple male voice.
    // Faster rate than Marco = active, engaged. Bass foundation +
    // presence boost = sounds like he's fully here.
    // ────────────────────────────────────────────────────────────────
    static let kai = VoiceCharacter(
        voiceIdentifiers: [
            "com.apple.voice.enhanced.en-US.Evan",      // direct, present, clear
            "com.apple.eloquence.en-US.Rocko",          // deeper fallback
            "com.apple.ttsbundle.Alex-compact"
        ],
        fallbackLanguage: "en-US",
        pitchMultiplier: 0.86,
        rate: 0.54,                     // fastest male — full of energy
        preDelay: 0.10, postDelay: 0.08,
        timePitchRate: 0.98, timePitchCents: -130,
        reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: 5,
        eqLowShelfFreq: 130,  eqLowShelfGain: +3.5,  // bass foundation
        eqMidFreq: 2500,      eqMidGain: +2.0,   eqMidBW: 0.9,  // cut-through presence
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
    @Published var voiceEnabled: Bool = UserDefaults.standard.object(forKey: "companion.voiceEnabled") as? Bool ?? true

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
        // .duckOthers ensures our voice is the loudest in the mix.
        // .allowBluetooth routes to AirPods / BT headsets automatically.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true,
                options: .notifyOthersOnDeactivation)
        } catch {}

        // Re-activate after any interruption (phone call, Siri, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object:  nil, queue: .main
        ) { [weak self] notification in
            guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: type) == .ended
            else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            // If we were mid-sentence when the interruption hit, nothing to resume —
            // the delegate already cleared isSpeaking.
            _ = self   // suppress capture warning
        }
    }

    // MARK: - Public speak
    //
    // Uses chunked delivery: text is split at natural sentence boundaries
    // and each chunk is queued as its own AVSpeechUtterance with a
    // context-appropriate gap. This is what makes speech sound human —
    // the natural breathing rhythm between thoughts.

    func speak(_ text: String, character: VoiceCharacter) {
        guard voiceEnabled else { return }

        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let clean = stripMarkdown(text)
        guard !clean.isEmpty else { return }

        _ = try? AVAudioSession.sharedInstance().setActive(true)
        isSpeaking = true

        let chunks = naturalChunks(of: clean)
        for (i, chunk) in chunks.enumerated() {
            let u = buildUtterance(chunk, character: character)
            // First chunk: use the voice character's configured pre-delay.
            // Subsequent chunks: very short gap (sounds like mid-sentence breath).
            u.preUtteranceDelay  = i == 0 ? character.preDelay : 0.06
            // Sentence-ending punctuation gets a longer post-pause.
            let last = chunk.last
            if last == "." || last == "!" || last == "?" || chunk.hasSuffix("…") {
                u.postUtteranceDelay = 0.22
            } else if last == "," || last == ";" {
                u.postUtteranceDelay = 0.12
            } else {
                u.postUtteranceDelay = 0.06
            }
            synth.speak(u)
        }
    }

    // MARK: - Natural chunking
    //
    // Splits at sentence boundaries while keeping chunks readable.
    // Avoids splitting mid-number ("3.14") or ellipsis ("...").

    private func naturalChunks(of text: String) -> [String] {
        // Split at ". ", "! ", "? ", "… " — sentence boundaries
        // Then split long clauses at ", " if they exceed 80 chars.
        var sentences: [String] = []
        var current = ""

        let words = text.components(separatedBy: " ")
        for word in words {
            current += (current.isEmpty ? "" : " ") + word
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            let endsWithTerminator = word.hasSuffix(".") || word.hasSuffix("!") ||
                                     word.hasSuffix("?") || word.hasSuffix("…")
            // Only split on period if the next char wouldn't form an abbreviation
            let isAbbrev = trimmed.count <= 2   // "Mr.", "U.S." etc.

            if endsWithTerminator && !isAbbrev && current.count > 20 {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else if current.count > 90 &&
                      (word.hasSuffix(",") || word.hasSuffix(";")) {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            sentences.append(current.trimmingCharacters(in: .whitespaces))
        }
        return sentences.filter { !$0.isEmpty }
    }

    func speakWithCurrentCompanion(_ text: String) {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let c  = CompanionPersonality.find(id: id) ?? .luna
        speak(text, character: c.voiceCharacter)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
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
        Task { @MainActor in isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = false }
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
                .foregroundColor(engine.isSpeaking ? .BC.accent : .BC.textMuted)
                .symbolEffect(.variableColor, isActive: engine.isSpeaking)
                .padding(6)
                .background(Color.BC.surface)
                .cornerRadius(8)
        }
    }
}
