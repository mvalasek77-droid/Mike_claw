import SwiftUI

// MARK: - Main Chat View
// Terminal-inspired dark UI with green accents — the "Openclaw" aesthetic.

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var inputFocused: Bool
    @State private var scrollProxy: ScrollViewProxy?

    let initialConversation: Conversation
    @StateObject private var vmHolder = VMHolder()

    // Lazily vend the real VM once appState is injected
    private var vm: ChatViewModel { vmHolder.vm! }

    init(conversation: Conversation) {
        self.initialConversation = conversation
    }

    // Helper class to hold the ViewModel
    private final class VMHolder: ObservableObject {
        var vm: ChatViewModel?
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                messageList
                inputBar
            }
        }
        .navigationTitle(vm.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.clearError() } }
        )) {
            Button("OK") { vm.clearError() }
        } message: {
            Text(vm.error ?? "")
        }
        .onAppear {
            if vmHolder.vm == nil {
                vmHolder.vm = ChatViewModel(conversation: initialConversation, appState: appState)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                    if vm.isThinking && vm.conversation.messages.last?.role != .assistant {
                        ThinkingIndicator()
                            .id("thinking")
                    }
                    Color.clear.frame(height: 80).id("bottom")
                }
                .padding(.top, 8)
            }
            .background(Color.black)
            .onChange(of: vm.conversation.messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: vm.isThinking) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color(white: 0.15))
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
                    .tint(.green)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        Task { await vm.send() }
                    }

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isThinking ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(vm.inputText.isEmpty && !vm.isThinking ? .gray : .green)
                }
                .disabled(vm.inputText.isEmpty && !vm.isThinking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(role: .destructive) {
                    vm.clearConversation()
                } label: {
                    Label("Clear conversation", systemImage: "trash")
                }

                Button {
                    // Rename handled inline
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                if !appState.availableTools.isEmpty {
                    Divider()
                    Label("\(appState.availableTools.count) tools active", systemImage: "wrench")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: Message

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .tool:
            toolResultRow
        case .system:
            EmptyView()
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(.system(.body, design: .default))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.green)
                .clipShape(BubbleShape(isUser: true))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool uses
            ForEach(message.toolUses) { toolUse in
                ToolUseRow(toolUse: toolUse)
            }

            // Text content
            if !message.content.isEmpty {
                HStack(alignment: .bottom) {
                    AssistantAvatar()
                    MarkdownText(message.content, isStreaming: message.isStreaming)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.1))
                        .clipShape(BubbleShape(isUser: false))
                        .textSelection(.enabled)
                    Spacer(minLength: 40)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var toolResultRow: some View {
        // Tool results are embedded in ToolUseRow, not shown separately
        EmptyView()
    }
}

// MARK: - Tool Use Row

struct ToolUseRow: View {
    let toolUse: ToolUse
    @State private var isExpanded = false

    private var statusColor: Color {
        switch toolUse.status {
        case .running: return .yellow
        case .success: return .green
        case .failure: return .red
        }
    }

    private var statusIcon: String {
        switch toolUse.status {
        case .running: return "clock"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Text(toolUse.toolName.components(separatedBy: "__").last ?? toolUse.toolName)
                        .font(.caption.monospaced())
                        .foregroundColor(.cyan)
                    Spacer()
                    Image(systemName: statusIcon)
                        .font(.caption)
                        .foregroundColor(statusColor)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !toolUse.input.isEmpty {
                        Text("Input")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                        Text(formatInput(toolUse.input))
                            .font(.caption.monospaced())
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                    if let result = toolUse.result {
                        Divider().background(Color(white: 0.15)).padding(.horizontal, 12)
                        Text("Result")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        Text(result)
                            .font(.caption.monospaced())
                            .foregroundColor(toolUse.status == .failure ? .red.opacity(0.8) : .green.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
                }
                .background(Color(white: 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
    }

    private func formatInput(_ input: [String: AnyCodable]) -> String {
        input.map { "\($0.key): \($0.value.value)" }.joined(separator: "\n")
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    @State private var dotCount = 1
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            AssistantAvatar()
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.green.opacity(i < dotCount ? 1 : 0.2))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.1))
            .clipShape(BubbleShape(isUser: false))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}

// MARK: - Assistant Avatar

struct AssistantAvatar: View {
    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 14))
            .foregroundColor(.green)
            .frame(width: 28, height: 28)
            .background(Color(white: 0.12))
            .clipShape(Circle())
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let tail: CGFloat = 6
        var path = Path()

        if isUser {
            path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tail, height: rect.height), cornerSize: CGSize(width: r, height: r))
        } else {
            path.addRoundedRect(in: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height), cornerSize: CGSize(width: r, height: r))
        }
        return path
    }
}

// MARK: - Markdown Text (simple inline rendering)

struct MarkdownText: View {
    let text: String
    let isStreaming: Bool

    init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    var body: some View {
        Text(parseMarkdown(text) + (isStreaming ? "▋" : ""))
            .font(.system(.body, design: .default))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlinesOnlyPreservingWhitespace)))
        ?? AttributedString(text)
    }
}
