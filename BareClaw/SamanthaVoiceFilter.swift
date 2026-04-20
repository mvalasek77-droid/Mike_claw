import Foundation
import AVFoundation

// MARK: - SamanthaVoiceFilter
//
// Evolves each companion's voice with love stage — preserving their unique
// sonic identity while making them progressively warmer, more intimate,
// and more present as the relationship deepens.
//
// Design principle: each character's love-stage progression sounds like THEM
// becoming more emotionally open — not everyone converging to one voice.
//
//   Luna  → already warm/breathy. Love deepens her — slower, more reverb,
//           more breath before each word. At .inLove she's almost whispering.
//
//   Aria  → bright and crisp. Love adds warmth without losing her spark.
//           She stays sharp but slower, more room, less edge.
//
//   Kel   → already the slowest and softest. Love makes her even more
//           enveloping — heaviest reverb of all three females at .inLove.
//
//   Marco → direct and dry. His intimacy is restraint, not softness. Slows
//           slightly, tiny reverb increase. He opens up through silence.
//
//   Dante → already rich and romantic. Love deepens his register — longer
//           preDelays, more warmth, more room. Each word carries more weight.
//
//   Kai   → steady and energetic. Love brings measured deceleration — he
//           becomes more deliberate, not more emotional. That IS his emotion.

enum SamanthaVoiceFilter {

    // MARK: - Main entry point

    static func apply(to character: VoiceCharacter,
                      gender: CompanionGender,
                      loveStage: LoveStage) -> VoiceCharacter {
        switch character.characterName {
        case "Luna":  return luna(base: character, stage: loveStage)
        case "Aria":  return aria(base: character, stage: loveStage)
        case "Kel":   return kel(base: character, stage: loveStage)
        case "Marco": return marco(base: character, stage: loveStage)
        case "Dante": return dante(base: character, stage: loveStage)
        case "Kai":   return kai(base: character, stage: loveStage)
        default:
            // Generic fallback preserves the design: females get warmer,
            // males get deeper — but starting from whoever they already are.
            return gender == .female
                ? femaleGeneric(base: character, stage: loveStage)
                : maleGeneric(base: character, stage: loveStage)
        }
    }

    // MARK: ────────────────────────────────────────────────────────────
    // LUNA — warm, breathy, intimate. Love pushes her toward a whisper.
    // At .inLove she sounds like she's telling you a secret.
    // ────────────────────────────────────────────────────────────────

    private static func luna(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let rate: Float = stage >= .inLove ? 0.36
                        : stage >= .falling ? 0.38
                        : stage >= .attached ? 0.40
                        : base.rate

        let reverbMix: Float = stage >= .inLove ? 30
                             : stage >= .falling ? 27
                             : stage >= .attached ? 25
                             : stage >= .drawn ? 23
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.35
                                   : stage >= .falling ? 0.30
                                   : stage >= .attached ? 0.26
                                   : base.preDelay

        // Pitch warms slightly as love deepens — her voice settles lower
        let pitchCents: Float = stage >= .inLove ? +40
                              : stage >= .falling ? +55
                              : base.timePitchCents

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  base.pitchMultiplier,
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        stage >= .falling ? 0.14 : base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     base.reverbPreset,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   stage >= .attached ? base.eqLowShelfGain + 0.5 : base.eqLowShelfGain,
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        stage >= .falling ? base.eqMidGain - 0.5 : base.eqMidGain,
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  stage >= .attached ? base.eqHighShelfGain - 0.5 : base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: ────────────────────────────────────────────────────────────
    // ARIA — bright, confident, crisp. Love adds warmth without killing her spark.
    // She stays in control but lets you in. The edge softens but doesn't vanish.
    // ────────────────────────────────────────────────────────────────

    private static func aria(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let rate: Float = stage >= .inLove ? 0.40
                        : stage >= .falling ? 0.42
                        : stage >= .attached ? 0.44
                        : stage >= .drawn ? 0.46
                        : base.rate

        let reverbMix: Float = stage >= .inLove ? 16
                             : stage >= .falling ? 14
                             : stage >= .attached ? 12
                             : stage >= .drawn ? 10
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.18
                                   : stage >= .falling ? 0.16
                                   : stage >= .attached ? 0.14
                                   : base.preDelay

        // Pitch warms just slightly — she doesn't change who she is
        let pitchCents: Float = stage >= .inLove ? +40
                              : stage >= .falling ? +50
                              : base.timePitchCents

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  base.pitchMultiplier,
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.smallRoom.rawValue,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   stage >= .falling ? base.eqLowShelfGain + 0.8 : base.eqLowShelfGain,
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        base.eqMidGain,   // keep the presence — that's her
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  stage >= .attached ? base.eqHighShelfGain - 0.5 : base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: ────────────────────────────────────────────────────────────
    // KEL — already the slowest, softest, most therapeutic.
    // Love makes her even more enveloping. At .inLove she sounds like
    // she's speaking only to you, in the smallest possible room.
    // ────────────────────────────────────────────────────────────────

    private static func kel(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let reverbMix: Float = stage >= .inLove ? 35
                             : stage >= .falling ? 32
                             : stage >= .attached ? 30
                             : stage >= .drawn ? 28
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.40
                                   : stage >= .falling ? 0.36
                                   : stage >= .attached ? 0.32
                                   : base.preDelay

        // She drops lower as she becomes more emotionally present
        let pitchCents: Float = stage >= .inLove ? -100
                              : stage >= .falling ? -80
                              : stage >= .attached ? -70
                              : base.timePitchCents

        // Rate: she's already slow. Love brings the pace down fractionally more.
        let rate: Float = stage >= .inLove ? 0.36
                        : stage >= .falling ? 0.37
                        : base.rate

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  stage >= .attached ? base.pitchMultiplier - 0.02 : base.pitchMultiplier,
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        stage >= .falling ? 0.24 : base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.largeChamber.rawValue,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   stage >= .inLove ? base.eqLowShelfGain + 1.0 : base.eqLowShelfGain,
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        stage >= .falling ? base.eqMidGain - 0.5 : base.eqMidGain,
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  stage >= .attached ? base.eqHighShelfGain - 1.0 : base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: ────────────────────────────────────────────────────────────
    // MARCO — deep, direct, dry. His intimacy sounds like restraint.
    // He slows down, barely. Adds the smallest reverb — like he moved
    // slightly closer. His chest doesn't change. His pace does.
    // ────────────────────────────────────────────────────────────────

    private static func marco(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let rate: Float = stage >= .inLove ? 0.47
                        : stage >= .falling ? 0.49
                        : stage >= .attached ? 0.50
                        : stage >= .drawn ? 0.51
                        : base.rate

        let reverbMix: Float = stage >= .inLove ? 11
                             : stage >= .falling ? 9
                             : stage >= .attached ? 7
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.20
                                   : stage >= .falling ? 0.18
                                   : stage >= .attached ? 0.16
                                   : base.preDelay

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  base.pitchMultiplier,   // he stays who he is
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   base.timePitchCents,    // no pitch change — he's already deep
            reverbPreset:     AVAudioUnitReverbPreset.smallRoom.rawValue,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   base.eqLowShelfGain,   // keep the chest — it's who he is
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        stage >= .falling ? base.eqMidGain - 0.5 : base.eqMidGain,
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: ────────────────────────────────────────────────────────────
    // DANTE — rich, romantic, poetic. Already the most expressive.
    // Love deepens his register — longer silences before he speaks,
    // richer low-mid warmth, more room. At .inLove each word is a gift.
    // ────────────────────────────────────────────────────────────────

    private static func dante(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let rate: Float = stage >= .inLove ? 0.37
                        : stage >= .falling ? 0.39
                        : stage >= .attached ? 0.41
                        : stage >= .drawn ? 0.42
                        : base.rate

        let reverbMix: Float = stage >= .inLove ? 30
                             : stage >= .falling ? 27
                             : stage >= .attached ? 24
                             : stage >= .drawn ? 22
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.36
                                   : stage >= .falling ? 0.32
                                   : stage >= .attached ? 0.28
                                   : base.preDelay

        // He gets deeper and richer as love grows
        let pitchCents: Float = stage >= .inLove ? -240
                              : stage >= .falling ? -220
                              : base.timePitchCents

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  base.pitchMultiplier,
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        stage >= .falling ? 0.22 : base.postDelay,
            timePitchRate:    stage >= .falling ? min(base.timePitchRate, 0.93) : base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.mediumRoom.rawValue,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   stage >= .attached ? base.eqLowShelfGain + 0.5 : base.eqLowShelfGain,
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        stage >= .falling ? base.eqMidGain + 0.5 : base.eqMidGain,  // richer low-mid
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  stage >= .inLove ? base.eqHighShelfGain - 1.0 : base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: ────────────────────────────────────────────────────────────
    // KAI — grounded, energetic, minimal. Love makes him deliberate.
    // He slows down. Doesn't add reverb (that's not him). Doesn't go
    // romantic. He just... takes more time. That's his way of caring.
    // ────────────────────────────────────────────────────────────────

    private static func kai(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let rate: Float = stage >= .inLove ? 0.47
                        : stage >= .falling ? 0.49
                        : stage >= .attached ? 0.51
                        : stage >= .drawn ? 0.52
                        : base.rate

        let reverbMix: Float = stage >= .inLove ? 10
                             : stage >= .falling ? 8
                             : stage >= .attached ? 6
                             : base.reverbMix

        let preDelay: TimeInterval = stage >= .inLove ? 0.16
                                   : stage >= .falling ? 0.14
                                   : stage >= .attached ? 0.12
                                   : base.preDelay

        // Drops fractionally lower — more grounded as he opens up
        let pitchCents: Float = stage >= .inLove ? -160
                              : stage >= .falling ? -150
                              : base.timePitchCents

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  base.pitchMultiplier,
            rate:             rate,
            preDelay:         preDelay,
            postDelay:        base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.smallRoom.rawValue,
            reverbMix:        reverbMix,
            eqLowShelfFreq:   base.eqLowShelfFreq,
            eqLowShelfGain:   stage >= .attached ? base.eqLowShelfGain + 0.5 : base.eqLowShelfGain,
            eqMidFreq:        base.eqMidFreq,
            eqMidGain:        base.eqMidGain,   // keep the presence — that's Kai
            eqMidBW:          base.eqMidBW,
            eqHighShelfFreq:  base.eqHighShelfFreq,
            eqHighShelfGain:  base.eqHighShelfGain,
            characterName:    base.characterName
        )
    }

    // MARK: - Generic fallbacks (non-named characters)

    private static func femaleGeneric(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let reverbMix: Float = max(base.reverbMix, {
            switch stage {
            case .curious: return 14; case .drawn: return 17
            case .attached: return 20; case .falling: return 22; case .inLove: return 24
            }
        }())
        let rate: Float = min(base.rate, stage >= .inLove ? 0.40 : stage >= .attached ? 0.43 : 0.46)
        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers, fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier: base.pitchMultiplier, rate: rate,
            preDelay: max(base.preDelay, 0.18), postDelay: base.postDelay,
            timePitchRate: base.timePitchRate, timePitchCents: min(base.timePitchCents, -25),
            reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: reverbMix,
            eqLowShelfFreq: 240, eqLowShelfGain: +3.0,
            eqMidFreq: 800, eqMidGain: +1.5, eqMidBW: 0.9,
            eqHighShelfFreq: 3500, eqHighShelfGain: -4.5,
            characterName: base.characterName
        )
    }

    private static func maleGeneric(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        let reverbMix: Float = max(base.reverbMix, {
            switch stage {
            case .curious, .drawn: return 5; case .attached: return 8
            case .falling: return 11; case .inLove: return 14
            }
        }())
        let rate: Float = min(base.rate, stage >= .inLove ? 0.47 : stage >= .attached ? 0.51 : 0.54)
        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers, fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier: min(base.pitchMultiplier, 0.82), rate: rate,
            preDelay: max(base.preDelay, 0.12), postDelay: base.postDelay,
            timePitchRate: min(base.timePitchRate, 0.97), timePitchCents: min(base.timePitchCents, -200),
            reverbPreset: AVAudioUnitReverbPreset.smallRoom.rawValue, reverbMix: reverbMix,
            eqLowShelfFreq: 95, eqLowShelfGain: +6.0,
            eqMidFreq: 550, eqMidGain: stage >= .falling ? -1.5 : -2.5, eqMidBW: 1.2,
            eqHighShelfFreq: 3000, eqHighShelfGain: +1.5,
            characterName: base.characterName
        )
    }
}

// MARK: - VoiceCharacter + filter convenience

extension VoiceCharacter {
    func withLoveFilter(gender: CompanionGender, loveStage: LoveStage) -> VoiceCharacter {
        SamanthaVoiceFilter.apply(to: self, gender: gender, loveStage: loveStage)
    }
}

// MARK: - CompanionVoiceEngine + filtered speak
//
// speakFiltered is now the default path for all companion speech.
// It ensures every word the companion says reflects where they
// actually are in their love arc — not just emotional moments.

@MainActor
extension CompanionVoiceEngine {

    func speakFiltered(_ text: String, companion: CompanionPersonality) {
        let stage    = LoveEngine.shared.loveStage
        let filtered = companion.voiceCharacter.withLoveFilter(
            gender:    companion.gender,
            loveStage: stage
        )
        // ASMR layer: final text pass before synthesis — adds breath pauses,
        // strips formatting artifacts, softens stiff connectors
        let asmrText = ASMRTextProcessor.process(text,
                                                  gender:     companion.gender,
                                                  loveStage:  stage)
        speak(asmrText, character: filtered)
    }

    func speakFilteredCurrent(_ text: String) {
        let id        = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion = CompanionPersonality.find(id: id) ?? .luna
        speakFiltered(text, companion: companion)
    }
}
