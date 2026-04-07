import Foundation
import AVFoundation

// MARK: - CompanionVoiceEngine
//
// Wraps AVSpeechSynthesizer to give each companion a distinct voice character.
// Pitch, rate, and voice variant are all per-companion.
// Also provides a "speak last message" quick action from the chat UI.

@MainActor
final class CompanionVoiceEngine: NSObject, ObservableObject {

    static let shared = CompanionVoiceEngine()

    @Published var isSpeaking: Bool = false
    @Published var voiceEnabled: Bool = {
        UserDefaults.standard.bool(forKey: "companion.voiceEnabled")
    }()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio session setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    // MARK: - Speak

    /// Speak `text` using the companion's voice profile.
    /// Strips markdown formatting so it sounds natural.
    func speak(_ text: String, using profile: CompanionVoiceProfile) {
        guard voiceEnabled else { return }
        stopSpeaking()

        let cleaned = stripMarkdown(text)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)

        // Apply voice profile
        utterance.voice = resolveVoice(identifier: profile.voiceIdentifier)
        utterance.pitchMultiplier = max(0.5, min(2.0, profile.pitchMultiplier))
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, profile.rate))
        utterance.preUtteranceDelay  = profile.preDelay
        utterance.postUtteranceDelay = profile.postDelay

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Speak using the currently selected companion's profile.
    func speakWithCurrentCompanion(_ text: String) {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion = CompanionPersonality.find(id: id) ?? .luna
        speak(text, using: companion.voiceProfile)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Toggle

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: "companion.voiceEnabled")
        if !voiceEnabled { stopSpeaking() }
    }

    // MARK: - Voice resolution
    //
    // Best-effort resolution: tries the exact identifier, then language prefix,
    // then defaults to current locale.

    private func resolveVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        // Try exact identifier first (works on device, may not on simulator)
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        // Extract language code (e.g. "en-US") and pick best available
        let parts = identifier.components(separatedBy: ".")
        if let lang = parts.last {
            if let voice = AVSpeechSynthesisVoice(language: lang) {
                return voice
            }
        }
        // Fallback: system default
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - Markdown stripper

    private func stripMarkdown(_ text: String) -> String {
        var s = text
        // Remove bold/italic markers
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "*",  with: "")
        s = s.replacingOccurrences(of: "_",  with: "")
        // Remove code blocks
        s = s.replacingOccurrences(of: "`", with: "")
        // Remove headers
        s = s.replacingOccurrences(of: "# ", with: "")
        s = s.replacingOccurrences(of: "## ", with: "")
        // Remove emoji (optional — keep them, TTS just skips them)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension CompanionVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                        didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}

// MARK: - Voice speak button (used in ChatView)

import SwiftUI

struct CompanionVoiceSpeakButton: View {
    let message: String
    @ObservedObject var engine = CompanionVoiceEngine.shared

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
                .foregroundColor(.OC.textMuted)
                .padding(6)
                .background(Color.OC.surface)
                .cornerRadius(8)
        }
    }
}
