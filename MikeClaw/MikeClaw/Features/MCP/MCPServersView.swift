import SwiftUI

// MARK: - MCP Servers Management

struct MCPServersView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false
    @State private var editingServer: MCPServerConfig?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("MCP Tools")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddServer = true } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.green)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task { await appState.refreshTools() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(appState.isToolsLoading ? .gray : .green)
                    }
                    .disabled(appState.isToolsLoading)
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddMCPServerView()
            }
            .sheet(item: $editingServer) { server in
                AddMCPServerView(editingServer: server)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.mcpServers.isEmpty && appState.availableTools.isEmpty {
            emptyState
        } else {
            List {
                // Servers section
                if !appState.mcpServers.isEmpty {
                    Section {
                        ForEach(appState.mcpServers) { server in
                            ServerRow(server: server) {
                                appState.toggleMCPServer(server.id)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    appState.removeMCPServer(server.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingServer = server
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        SectionHeader(title: "Servers", icon: "server.rack")
                    }
                    .listRowBackground(Color(white: 0.08))
                }

                // Discovered tools section
                if !appState.availableTools.isEmpty {
                    Section {
                        ForEach(appState.availableTools) { tool in
                            ToolRow(tool: tool)
                        }
                    } header: {
                        SectionHeader(
                            title: "Available Tools (\(appState.availableTools.count))",
                            icon: "wrench.and.screwdriver",
                            isLoading: appState.isToolsLoading
                        )
                    }
                    .listRowBackground(Color(white: 0.08))
                }

                // Preset servers
                Section {
                    PresetServerRow(
                        name: "Brave Search",
                        description: "Web search via Brave MCP",
                        icon: "magnifyingglass",
                        urlString: "https://mcp.bravesearch.com"
                    ) { url in
                        appState.addMCPServer(MCPServerConfig(
                            name: "Brave Search",
                            transport: .streamableHTTP,
                            url: URL(string: url)
                        ))
                    }

                    PresetServerRow(
                        name: "Custom Server",
                        description: "Add your own MCP endpoint",
                        icon: "plus.square",
                        urlString: ""
                    ) { _ in showAddServer = true }

                } header: {
                    SectionHeader(title: "Add Server", icon: "plus.circle")
                }
                .listRowBackground(Color(white: 0.08))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 52))
                .foregroundColor(.green.opacity(0.6))

            VStack(spacing: 8) {
                Text("No MCP Tools")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("Connect MCP servers to give Claude\ntools to use on your behalf.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

            Button { showAddServer = true } label: {
                Label("Add MCP Server", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }
}

// MARK: - Server Row

struct ServerRow: View {
    let server: MCPServerConfig
    let onToggle: () -> Void

    var toolCount: Int { 0 }  // Derived from appState in real usage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                    .foregroundColor(.white)
                if let url = server.url {
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Text(server.transport.rawValue)
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .tint(.green)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let tool: MCPTool

    var displayName: String {
        tool.name.components(separatedBy: "__").last ?? tool.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "function")
                    .font(.caption)
                    .foregroundColor(.cyan)
                Text(displayName)
                    .font(.subheadline.monospaced())
                    .foregroundColor(.white)
            }
            if !tool.description.isEmpty {
                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preset Server Row

struct PresetServerRow: View {
    let name: String
    let description: String
    let icon: String
    let urlString: String
    let onAdd: (String) -> Void

    var body: some View {
        Button { onAdd(urlString) } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundColor(.green.opacity(0.7))
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(.gray)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.green)
            }
        }
    }
}
