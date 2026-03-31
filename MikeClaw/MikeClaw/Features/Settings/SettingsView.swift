import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAPIKey = false
    @State private var editingSystemPrompt = false

    let availableModels = [
        ("claude-sonnet-4-6", "Claude Sonnet 4.6 (Recommended)"),
        ("claude-opus-4-6", "Claude Opus 4.6 (Most Capable)"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5 (Fastest)")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    // API Key
                    Section {
                        HStack {
                            Text("API Key")
                                .foregroundColor(.gray)
                            Spacer()
                            if showAPIKey {
                                TextField("sk-ant-...", text: $appState.apiKey)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            } else {
                                SecureField("sk-ant-...", text: $appState.apiKey)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                            }
                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                        .listRowBackground(Color(white: 0.1))

                        if appState.apiKey.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                                Text("Enter your Anthropic API key to use MikeClaw")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            .listRowBackground(Color(white: 0.1))
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("API key saved to Keychain")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .listRowBackground(Color(white: 0.1))
                        }
                    } header: {
                        SectionHeader(title: "Anthropic API", icon: "key")
                    } footer: {
                        Text("Your API key is stored securely in the iOS Keychain and is only sent directly to api.anthropic.com. It never passes through any third-party servers.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Model selection
                    Section {
                        Picker("Model", selection: $appState.selectedModel) {
                            ForEach(availableModels, id: \.0) { model in
                                Text(model.1).tag(model.0)
                            }
                        }
                        .tint(.green)
                        .listRowBackground(Color(white: 0.1))
                    } header: {
                        SectionHeader(title: "Model", icon: "cpu")
                    }

                    // System prompt
                    Section {
                        Button {
                            editingSystemPrompt = true
                        } label: {
                            HStack {
                                Text("System Prompt")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .listRowBackground(Color(white: 0.1))

                        Button {
                            appState.defaultSystemPrompt = AppState.openClawSystemPrompt
                        } label: {
                            Text("Reset to Default")
                                .foregroundColor(.yellow)
                        }
                        .listRowBackground(Color(white: 0.1))
                    } header: {
                        SectionHeader(title: "Behavior", icon: "text.bubble")
                    }

                    // Tools summary
                    Section {
                        HStack {
                            Text("Connected Tools")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(appState.availableTools.count)")
                                .foregroundColor(appState.availableTools.isEmpty ? .gray : .green)
                        }
                        .listRowBackground(Color(white: 0.1))

                        HStack {
                            Text("MCP Servers")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(appState.mcpServers.filter(\.isEnabled).count) / \(appState.mcpServers.count)")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color(white: 0.1))
                    } header: {
                        SectionHeader(title: "Tools", icon: "wrench.and.screwdriver")
                    }

                    // About
                    Section {
                        HStack {
                            Text("Version")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("1.0.0")
                                .foregroundColor(.gray)
                        }
                        .listRowBackground(Color(white: 0.1))

                        HStack {
                            Text("Architecture")
                                .foregroundColor(.gray)
                            Spacer()
                            Text("Agentic · MCP · App Intents")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                        .listRowBackground(Color(white: 0.1))
                    } header: {
                        SectionHeader(title: "About", icon: "info.circle")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $editingSystemPrompt) {
                SystemPromptEditor(systemPrompt: $appState.defaultSystemPrompt)
            }
        }
    }
}

// MARK: - System Prompt Editor

struct SystemPromptEditor: View {
    @Binding var systemPrompt: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TextEditor(text: $systemPrompt)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .tint(.green)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
            }
            .navigationTitle("System Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
