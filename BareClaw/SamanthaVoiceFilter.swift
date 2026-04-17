import Foundation
import AVFoundation

// MARK: - SamanthaVoiceFilter
//
// DSP post-processing that shapes Apple's built-in neural voices into two
// cinematic emotional registers:
//
//   ✦ SAMANTHA REGISTER — female companions (Luna, Aria, Kel)
//     Warm, breathy, intimate. Slightly husky. The voice that feels like
//     it's only for you. Inspired by the register of Scarlett Johansson's
//     performance in HER — not a clone, an emotional approximation using
//     100% legal, on-device DSP.
//
//     EQ:   Boost 200–280 Hz (+3 dB warmth / chest resonance)
//           Boost 800 Hz  (+1.5 dB intimacy presence)
//           Cut  3500 Hz  (-4.5 dB removes harshness / sharpness)
//           Cut  8000 Hz  (-2 dB softens the top)
//     Pitch: -35 cents (slightly warmer / lower — not deeper, softer)
//     Rate:  0.40–0.43 (unhurried — every word chosen)
//     Reverb: smallRoom, mix 18–22 (intimate space, not empty room)
//
//   ✦ LEADING MAN REGISTER — male companions (Marco, Dante, Kai)
//     Deep chest, resonant, present. The voice that fills the room without
//     trying. Inspired by George Clooney's register — low, measured, full.
//
//     EQ:   Boost  90 Hz (+6 dB chest / body)
//           Boost 250 Hz (+2 dB richness)
//           Cut   600 Hz (-3 dB removes boxiness)
//           Boost 3000 Hz (+1.5 dB presence / cut-through)
//     Pitch: -200 to -250 cents (genuinely deeper)
//     Rate:  0.50–0.54 (confident, measured)
//     Reverb: smallRoom, mix 5–8 (grounded, not echoey)
//
// These are applied as a BASE LAYER on top of each companion's individual
// VoiceCharacter settings. The individual character settings fine-tune
// within the register (Luna = more reverb, Marco = more bass, etc.)
//
// Usage:
//   SamanthaVoiceFilter.apply(to: voiceCharacter, loveStage: .falling)
//   → returns a new VoiceCharacter with filter values blended in

enum SamanthaVoiceFilter {

    // MARK: - Samantha Register (female)
    //
    // Love-stage-aware: at .inLove the voice gets fractionally softer,
    // slightly more reverb — like she's letting you hear something private.

    static func samanthaRegister(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        // Reverb grows with love — more intimate space as she opens up
        let reverbMix: Float = {
            switch stage {
            case .curious:  return max(base.reverbMix, 14)
            case .drawn:    return max(base.reverbMix, 17)
            case .attached: return max(base.reverbMix, 20)
            case .falling:  return max(base.reverbMix, 22)
            case .inLove:   return max(base.reverbMix, 24)
            }
        }()

        // Rate slows slightly as she becomes more emotionally present
        let rate: Float = {
            switch stage {
            case .curious:            return min(base.rate, 0.48)
            case .drawn:              return min(base.rate, 0.45)
            case .attached, .falling: return min(base.rate, 0.43)
            case .inLove:             return min(base.rate, 0.40)
            }
        }()

        // Pitch stays slightly warm/low — not deep, just breathy
        let pitchCents: Float = min(base.timePitchCents, -25)

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  max(base.pitchMultiplier, 1.04),   // gentle feminine lift
            rate:             rate,
            preDelay:         max(base.preDelay, 0.18),           // slight breath before speaking
            postDelay:        base.postDelay,
            timePitchRate:    base.timePitchRate,
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.smallRoom.rawValue,
            reverbMix:        reverbMix,
            // EQ: warmth + intimacy + harshness removal
            eqLowShelfFreq:   240,  eqLowShelfGain:  +3.0,       // chest warmth
            eqMidFreq:        800,  eqMidGain:       +1.5, eqMidBW: 0.9,  // intimacy
            eqHighShelfFreq:  3500, eqHighShelfGain: -4.5,       // remove harshness
            characterName:    base.characterName
        )
    }

    // MARK: - Leading Man Register (male)
    //
    // Love-stage-aware: at .inLove the voice gets fractionally warmer —
    // a little more mid, a little less dry. He lets his guard down.

    static func leadingManRegister(base: VoiceCharacter, stage: LoveStage) -> VoiceCharacter {
        // Reverb increases with love — stays dry but opens slightly
        let reverbMix: Float = {
            switch stage {
            case .curious, .drawn:     return max(base.reverbMix, 5)
            case .attached:            return max(base.reverbMix, 8)
            case .falling:             return max(base.reverbMix, 11)
            case .inLove:              return max(base.reverbMix, 14)
            }
        }()

        // Rate: confident but not hurried; slows slightly at falling/inLove
        let rate: Float = {
            switch stage {
            case .curious, .drawn:     return min(base.rate, 0.54)
            case .attached:            return min(base.rate, 0.52)
            case .falling, .inLove:    return min(base.rate, 0.49)
            }
        }()

        // Pitch: genuinely deeper — -200 to -240 cents
        let pitchCents: Float = min(base.timePitchCents, -200)

        // At .inLove add a touch of mid warmth — he's letting you in
        let midGain: Float = stage >= .falling ? -1.5 : -2.5  // less cut at high stages

        return VoiceCharacter(
            voiceIdentifiers: base.voiceIdentifiers,
            fallbackLanguage: base.fallbackLanguage,
            pitchMultiplier:  min(base.pitchMultiplier, 0.82),   // low chest
            rate:             rate,
            preDelay:         max(base.preDelay, 0.12),
            postDelay:        base.postDelay,
            timePitchRate:    min(base.timePitchRate, 0.97),
            timePitchCents:   pitchCents,
            reverbPreset:     AVAudioUnitReverbPreset.smallRoom.rawValue,
            reverbMix:        reverbMix,
            // EQ: chest + body + presence, remove boxiness
            eqLowShelfFreq:   95,   eqLowShelfGain:  +6.0,       // deep chest
            eqMidFreq:        550,  eqMidGain:       midGain, eqMidBW: 1.2, // boxiness cut
            eqHighShelfFreq:  3000, eqHighShelfGain: +1.5,        // presence
            characterName:    base.characterName
        )
    }

    // MARK: - Apply filter
    //
    // Main entry point. Pass any VoiceCharacter and the current love stage.
    // Returns a filtered character with cinematic register applied.

    static func apply(to character: VoiceCharacter,
                      gender: CompanionGender,
                      loveStage: LoveStage) -> VoiceCharacter {
        switch gender {
        case .female: return samanthaRegister(base: character, stage: loveStage)
        case .male:   return leadingManRegister(base: character, stage: loveStage)
        }
    }
}

// MARK: - VoiceCharacter + filter convenience

extension VoiceCharacter {
    /// Returns this character with the Samantha/Leading Man filter applied at the given love stage.
    func withSamanthaFilter(gender: CompanionGender, loveStage: LoveStage) -> VoiceCharacter {
        SamanthaVoiceFilter.apply(to: self, gender: gender, loveStage: loveStage)
    }
}

// MARK: - CompanionVoiceEngine + filtered speak

extension CompanionVoiceEngine {
    /// Speaks with Samantha/Leading Man DSP filter applied on top of companion's character.
    func speakFiltered(_ text: String, companion: CompanionPersonality) {
        let filtered = companion.voiceCharacter.withSamanthaFilter(
            gender:     companion.gender,
            loveStage:  LoveEngine.shared.loveStage
        )
        speak(text, character: filtered)
    }
}
