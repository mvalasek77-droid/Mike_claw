import Security
import SwiftUI

// MARK: - Engine selection

enum DecodeEngineMode: String, CaseIterable, Identifiable {
    case auto
    case onDevice
    case apiKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .onDevice: return "On-Device Apple Intelligence"
        case .apiKey: return "My API Key"
        }
    }

    var detail: String {
        switch self {
        case .auto:
            return "ChadDrop picks the best available engine for each decode. Recommended."
        case .onDevice:
            return "Uses Apple's on-device foundation model. Private and offline, requires iOS 26 with Apple Intelligence."
        case .apiKey:
            return "Uses your own Anthropic (Claude) or OpenAI API key for the highest quality reads. The key never leaves this device except to call your AI provider."
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .onDevice: return "iphone.gen3"
        case .apiKey: return "key.fill"
        }
    }
}

enum EngineSettings {
    private static let modeKey = "chaddropEngineMode"

    static var mode: DecodeEngineMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let mode = DecodeEngineMode(rawValue: raw) else {
                return .auto
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }
}

// MARK: - Keychain storage for the API key

enum ChadDropKeychain {
    private static let service = "com.chaddrop.app"
    private static let account = "openai_api_key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func loadAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Settings screen

struct ChadDropSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: DecodeEngineMode = EngineSettings.mode
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = ChadDropKeychain.loadAPIKey() != nil
    @State private var statusMessage: String?

    private var onDeviceAvailable: Bool {
        AppleFoundationClient().isAvailable
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    enginePicker
                    if mode == .apiKey {
                        apiKeyPanel
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Engine")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            ForEach(DecodeEngineMode.allCases) { candidate in
                Button {
                    mode = candidate
                    EngineSettings.mode = candidate
                    statusMessage = nil
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.blush)
                            .frame(width: 28)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.label)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text(detailText(for: candidate))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.64))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(mode == candidate ? AppTheme.hotPink : .white.opacity(0.3))
                            .padding(.top, 2)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(mode == candidate ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(mode == candidate ? AppTheme.hotPink.opacity(0.5) : .white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("engineMode_\(candidate.rawValue)")
            }
        }
    }

    private func detailText(for candidate: DecodeEngineMode) -> String {
        if candidate == .onDevice && !onDeviceAvailable {
            return candidate.detail + " Not available on this device — ChadDrop will use its built-in engine instead."
        }
        return candidate.detail
    }

    private var apiKeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            if hasStoredKey {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.lime)
                    Text("A key is saved securely in your Keychain.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                    Spacer(minLength: 8)
                    Button("Remove") {
                        ChadDropKeychain.deleteAPIKey()
                        hasStoredKey = false
                        statusMessage = "API key removed."
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.peach)
                }
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
            }

            SecureField("sk-ant-... (Claude) or sk-... (OpenAI)", text: $apiKeyInput)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .tint(AppTheme.hotPink)
                .padding(12)
                .background(AppTheme.panel.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
                .accessibilityIdentifier("apiKeyField")

            Button {
                let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    statusMessage = "Paste your API key first."
                    return
                }
                if ChadDropKeychain.saveAPIKey(trimmed) {
                    hasStoredKey = true
                    apiKeyInput = ""
                    statusMessage = "API key saved. Decodes will now use your key."
                } else {
                    statusMessage = "Could not save the key. Please try again."
                }
            } label: {
                Text("Save Key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .accessibilityIdentifier("saveApiKeyButton")

            Text("Claude keys (sk-ant-...) and OpenAI keys (sk-...) are both supported — ChadDrop detects which one you saved. Your key is stored only in this device's Keychain and is used solely to call your AI provider when decoding. Get a key at console.anthropic.com or platform.openai.com.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(minHeight: 48)
            .padding(.horizontal, 16)
            .background(AppTheme.hotGradient.opacity(configuration.isPressed ? 0.74 : 1), in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
