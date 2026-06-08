import Foundation

/// An App Store localization the user can manage a caption set for. App Store
/// Connect localizes screenshots per language, so a single project can carry
/// every language's headlines and export them in one pass.
struct ASCLanguage: Identifiable, Hashable {
    /// App Store language code, e.g. "en-US".
    let code: String
    /// Human-readable label, e.g. "English (U.S.)".
    let name: String
    var id: String { code }

    /// The default language a new project starts in.
    static let base = "en-US"

    /// A curated list of the most common App Store storefront languages.
    static let catalog: [ASCLanguage] = [
        .init(code: "en-US", name: "English (U.S.)"),
        .init(code: "en-GB", name: "English (U.K.)"),
        .init(code: "es-ES", name: "Spanish (Spain)"),
        .init(code: "es-MX", name: "Spanish (Mexico)"),
        .init(code: "fr-FR", name: "French"),
        .init(code: "de-DE", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "pt-BR", name: "Portuguese (Brazil)"),
        .init(code: "nl-NL", name: "Dutch"),
        .init(code: "sv", name: "Swedish"),
        .init(code: "da", name: "Danish"),
        .init(code: "no", name: "Norwegian"),
        .init(code: "fi", name: "Finnish"),
        .init(code: "pl", name: "Polish"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh-Hans", name: "Chinese (Simplified)"),
        .init(code: "zh-Hant", name: "Chinese (Traditional)"),
        .init(code: "ar-SA", name: "Arabic"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "th", name: "Thai"),
        .init(code: "id", name: "Indonesian")
    ]

    static func named(_ code: String) -> ASCLanguage? {
        catalog.first { $0.code == code }
    }

    /// Best-effort display name for a code (falls back to the raw code).
    static func displayName(for code: String) -> String {
        named(code)?.name ?? code
    }
}
