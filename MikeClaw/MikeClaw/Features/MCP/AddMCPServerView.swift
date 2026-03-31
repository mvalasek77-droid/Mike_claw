import SwiftUI

// MARK: - Add / Edit MCP Server Sheet

struct AddMCPServerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var editingServer: MCPServerConfig?

    @State private var name = ""
    @State private var urlString = ""
    @State private var transport: MCPServerConfig.Transport = .streamableHTTP
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationSuccess = false

    var isEditing: Bool { editingServer != nil }
    var canSave: Bool { !name.isEmpty && URL(string: urlString) != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    Section {
                        HStack {
                            Text("Name")
                                .foregroundColor(.gray)
                            TextField("My MCP Server", text: $name)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                        }
                        .listRowBackground(Color(white: 0.1))

                        HStack {
                            Text("URL")
                                .foregroundColor(.gray)
                            TextField("https://...", text: $urlString)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .listRowBackground(Color(white: 0.1))

                        Picker("Transport", selection: $transport) {
                            ForEach(MCPServerConfig.Transport.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .tint(.green)
                        .listRowBackground(Color(white: 0.1))

                    } header: {
                        SectionHeader(title: "Server Configuration", icon: "server.rack")
                    } footer: {
                        Text("The server must expose a JSON-RPC endpoint that supports the MCP tools/list and tools/call methods.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Validation
                    Section {
                        Button {
                            Task { await validateServer() }
                        } label: {
                            HStack {
                                if isValidating {
                                    ProgressView().tint(.green)
                                } else {
                                    Image(systemName: validationSuccess ? "checkmark.circle.fill" : "network")
                                        .foregroundColor(validationSuccess ? .green : .cyan)
                                }
                                Text(isValidating ? "Testing connection..." : "Test Connection")
                                    .foregroundColor(validationSuccess ? .green : .white)
                            }
                        }
                        .disabled(!canSave || isValidating)
                        .listRowBackground(Color(white: 0.1))

                        if let error = validationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .listRowBackground(Color(white: 0.1))
                        }

                        if validationSuccess {
                            Text("Connection successful")
                                .font(.caption)
                                .foregroundColor(.green)
                                .listRowBackground(Color(white: 0.1))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundColor(canSave ? .green : .gray)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if let server = editingServer {
                name = server.name
                urlString = server.url?.absoluteString ?? ""
                transport = server.transport
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let url = URL(string: urlString) else { return }
        if isEditing, let existing = editingServer {
            // Update existing
            if let idx = appState.mcpServers.firstIndex(where: { $0.id == existing.id }) {
                appState.mcpServers[idx] = MCPServerConfig(
                    id: existing.id,
                    name: name,
                    transport: transport,
                    url: url,
                    isEnabled: existing.isEnabled
                )
            }
        } else {
            appState.addMCPServer(MCPServerConfig(
                name: name,
                transport: transport,
                url: url
            ))
        }
        dismiss()
    }

    private func validateServer() async {
        guard let url = URL(string: urlString) else { return }
        isValidating = true
        validationError = nil
        validationSuccess = false

        let testServer = MCPServerConfig(name: name, transport: transport, url: url)
        do {
            let tools = try await MCPService.shared.discoverTools(from: testServer)
            validationSuccess = true
            validationError = nil
            if !tools.isEmpty {
                validationError = nil
            }
        } catch {
            validationError = error.localizedDescription
        }
        isValidating = false
    }
}
