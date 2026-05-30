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

    /// Drafts a substantial long-form artifact the AI Editor can vet end-to-end:
    /// a manuscript scene for novels, lyrics + liner notes for music, an
    /// opening-scene screenplay for film. ~300-600 words. Returns nil if the
    /// on-device model is unavailable.
    ///
    /// This is what makes Scout's music/film slots vettable today on-device:
    /// the Editor analyses this prose as the artifact (since on-device gen
    /// can't produce real audio/video bytes). When a real media-generation
    /// provider is wired in later, that pathway can layer real bytes on top.
    static func draftLongForm(type: MediaType, title: String, genre: String,
                              formula: String, masters: [String]) async -> String? {
        let mastersClause: String
        if masters.isEmpty {
            mastersClause = ""
        } else {
            mastersClause = " Drawing on patterns from \(masters.prefix(2).joined(separator: " and "))."
        }
        let formulaClause = formula.isEmpty ? "" : " Formula: \(formula)."
        let titleClause = title.trimmed.isEmpty ? "" : " Title: \"\(title.trimmed)\"."
        let genreClause = genre.isEmpty ? "" : " Genre: \(genre)."

        let instructions: String
        let prompt: String
        switch type {
        case .novel:
            instructions = "You are a literary novelist. Write a vivid 400-600 word opening scene of a novel. Prose only — no headings, no metadata, no quotes wrapping the whole thing. Begin in the world; trust the reader."
            prompt = "Write the opening scene.\(titleClause)\(genreClause)\(mastersClause)\(formulaClause)"
        case .music:
            instructions = "You are a lyricist + producer. Write lyrics for the lead track of an album (verses, chorus, bridge), then a short paragraph of producer's liner notes describing the album's sound across its tracks. 350-500 words total. Format: song title on its own line, then lyrics with [Verse] / [Chorus] tags, then a blank line and the liner notes paragraph. No other preamble."
            prompt = "Compose the lead-track lyrics + liner notes for an album.\(titleClause)\(genreClause)\(mastersClause)\(formulaClause)"
        case .movie:
            instructions = "You are a screenwriter. Write a 400-600 word opening scene in proper screenplay format — slug lines (INT./EXT.), action lines, dialogue. Tight, visual writing. No preamble outside the screenplay."
            prompt = "Write the opening scene of the film.\(titleClause)\(genreClause)\(mastersClause)\(formulaClause)"
        }
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
