import AppIntents
import Foundation

// MARK: - App Shortcuts Provider
// Registers AppClaw's capabilities with Siri and Shortcuts

struct AppClawShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskClaudeIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$query)",
                "Hey \(.applicationName), \(\.$query)",
                "\(.applicationName) help me with \(\.$query)"
            ],
            shortTitle: "Ask Claude",
            systemImageName: "bubble.left.and.bubble.right"
        )

        AppShortcut(
            intent: QuickAnalysisIntent(),
            phrases: [
                "Analyze with \(.applicationName)",
                "\(.applicationName) quick analysis"
            ],
            shortTitle: "Quick Analysis",
            systemImageName: "magnifyingglass"
        )
    }
}

// MARK: - Ask Claude Intent
// Allows users to ask Claude a question via Siri or Shortcuts

struct AskClaudeIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Claude"
    static let description = IntentDescription(
        "Ask Claude a question and get an instant response.",
        categoryName: "AI Assistant"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Your question", description: "What would you like to ask?")
    var query: String

    @MainActor
    func perform() async throws -> some ProvidesDialog & ShowsSnippetView {
        let apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
        guard !apiKey.isEmpty else {
            throw IntentError.missingAPIKey
        }

        let systemPrompt = UserDefaults.standard.string(forKey: "default_system_prompt")
            ?? AppState.openClawSystemPrompt

        let messages = [Message(role: .user, content: query)]

        let response = try await ClaudeService.shared.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: [],  // No tools in Shortcut context for speed
            apiKey: apiKey
        )

        let answer = response.content.compactMap(\.text).joined(separator: "\n")
        let truncated = String(answer.prefix(500)) + (answer.count > 500 ? "..." : "")

        return .result(
            dialog: "\(truncated)",
            view: IntentResultView(query: query, response: truncated)
        )
    }
}

// MARK: - Quick Analysis Intent

struct QuickAnalysisIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Analysis"
    static let description = IntentDescription(
        "Run a quick analysis using Claude and available tools.",
        categoryName: "AI Assistant"
    )
    static let openAppWhenRun = true

    @Parameter(title: "What to analyze")
    var subject: String?

    @MainActor
    func perform() async throws -> some OpensIntent {
        // Opens the app and starts a new conversation with the subject pre-filled
        return .result()
    }
}

// MARK: - Intent Result View

struct IntentResultView: View {
    let query: String
    let response: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "pawprint.fill")
                    .foregroundColor(.green)
                Text("AppClaw")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }

            Text(query)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(2)

            Divider()

            Text(response)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(8)
        }
        .padding()
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Intent Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case missingAPIKey
    case responseEmpty

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in AppClaw Settings to use this shortcut."
        case .responseEmpty:
            return "No response was received from Claude."
        }
    }
}
