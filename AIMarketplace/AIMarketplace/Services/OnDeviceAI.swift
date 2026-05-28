import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device generative AI via Apple's Foundation Models framework (iOS 26+).
///
/// Because it calls the **system** language model, it always uses the latest
/// model Apple ships and improves automatically with OS updates — no app
/// changes needed. Everything runs on device: private, offline, and free.
///
/// Guarded so the app still builds/runs on older Xcode toolchains and iOS
/// versions (the framework simply isn't imported), falling back to nil.
@MainActor
enum OnDeviceAI {

    enum Status: Equatable {
        case ready
        case unavailable(String)   // present but not usable (reason)
        case unsupported           // OS/toolchain without Foundation Models

        var isReady: Bool { self == .ready }
    }

    /// Current availability of the on-device model.
    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let reason):
                return .unavailable(describe(reason))
            @unknown default:
                return .unavailable("Unavailable")
            }
        } else {
            return .unsupported
        }
        #else
        return .unsupported
        #endif
    }

    static var isReady: Bool { status.isReady }

    /// Generates text from the system model. Returns nil if unavailable or on error.
    static func generate(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Drafts a punchy marketplace synopsis for a work-in-progress.
    static func draftSynopsis(type: MediaType, title: String, genre: String, existing: String) async -> String? {
        let kind = type.title.lowercased()
        let instructions = "You are a marketing copywriter for an AI-media marketplace. Write a single vivid, commercial synopsis of 2–3 sentences. No preamble, no quotes, no markdown."
        var prompt = "Write a synopsis for a \(genre.isEmpty ? "" : genre + " ")\(kind)"
        if !title.trimmed.isEmpty { prompt += " titled \"\(title.trimmed)\"" }
        if existing.trimmed.count > 12 { prompt += ". Build on this draft: \(existing.trimmed)" }
        prompt += "."
        return await generate(instructions: instructions, prompt: prompt)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings."
        case .modelNotReady: return "The model is still downloading — try again shortly."
        @unknown default: return "On-device AI is unavailable right now."
        }
    }
    #endif
}
