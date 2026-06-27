import SwiftUI
import Foundation

/// A chat thread: message bubbles (yours trailing, theirs leading), a typing
/// indicator, delivery/read receipts, and an input bar. Auto-scrolls to the
/// newest message.
struct ChatView: View {
    @State private var model: ChatViewModel
    @State private var draft = ""
    @State private var isRecordingVoiceNote = false
    @FocusState private var inputFocused: Bool

    init(conversation: Conversation, service: MessagingService) {
        _model = State(initialValue: ChatViewModel(conversation: conversation, service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            thread
            inputBar
        }
        .navigationTitle(model.conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(model.conversation.displayTitle).font(Tokens.Typography.headline)
                    if model.partnerOnline {
                        Text("Active now")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .task { await model.load() }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.sm) {
                    ForEach(model.messages) { message in
                        MessageBubble(message: message, isGroup: model.conversation.isGroup)
                            .id(message.id)
                    }
                    if model.partnerTyping {
                        TypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(typingAnchor)
                    }
                }
                .padding(Tokens.Spacing.lg)
            }
            .onChange(of: model.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.partnerTyping) { _, typing in if typing { scrollToEnd(proxy) } }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(Tokens.Spacing.md)
                .liquidGlass(radius: Tokens.Radius.lg)

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VoiceNoteButton(isRecording: $isRecordingVoiceNote, onFinish: sendVoiceNote)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .accessibilityLabel("Send message")
            }
        }
        .padding(Tokens.Spacing.md)
        .background(.bar)
    }

    private let typingAnchor = "typing-indicator"

    private func send() {
        let text = draft
        draft = ""
        Task { await model.send(text) }
    }

    private func sendVoiceNote(duration: TimeInterval) {
        Task { await model.sendVoiceNote(duration: duration) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(Tokens.Motion.gentle) {
            if model.partnerTyping {
                proxy.scrollTo(typingAnchor, anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let isGroup: Bool

    var body: some View {
        VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
            if isGroup && !message.isMine {
                Text(message.sender.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .padding(.horizontal, Tokens.Spacing.sm)
            }
            content
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    if message.isMine {
                        RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
                            .fill(Tokens.Color.accent)
                    } else {
                        RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            if message.isMine {
                Text(message.status.label)
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .padding(.trailing, Tokens.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isMine ? "You" : message.sender.displayName): \(message.text)")
    }

    @ViewBuilder
    private var content: some View {
        if let duration = message.voiceNoteDuration {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "waveform")
                Text(durationLabel(duration))
                    .font(Tokens.Typography.body)
            }
            .foregroundStyle(message.isMine ? .white : Tokens.Color.textPrimary)
        } else {
            Text(message.text)
                .font(Tokens.Typography.body)
                .foregroundStyle(message.isMine ? .white : Tokens.Color.textPrimary)
        }
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Press-and-hold to record a voice note; release to send. Tracks elapsed
/// time so the sent message carries a real duration for the bubble to show.
private struct VoiceNoteButton: View {
    @Binding var isRecording: Bool
    let onFinish: (TimeInterval) -> Void

    @State private var startedAt: Date?

    var body: some View {
        Image(systemName: isRecording ? "mic.fill" : "mic")
            .font(.title2)
            .foregroundStyle(isRecording ? .red : Tokens.Color.accent)
            .padding(Tokens.Spacing.sm)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isRecording else { return }
                        isRecording = true
                        startedAt = .now
                        HapticsEngine.shared.play(.selectionChanged)
                    }
                    .onEnded { _ in
                        isRecording = false
                        guard let startedAt else { return }
                        let duration = max(1, Date.now.timeIntervalSince(startedAt))
                        self.startedAt = nil
                        onFinish(duration)
                    }
            )
            .accessibilityLabel("Hold to record a voice note")
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Tokens.Color.textSecondary)
                    .frame(width: 7, height: 7)
                    .opacity(dotOpacity(i))
            }
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.sm)
        .liquidGlass(radius: Tokens.Radius.lg)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
        .accessibilityLabel("Typing")
    }

    private func dotOpacity(_ index: Int) -> Double {
        reduceMotion ? 0.6 : 0.3 + 0.7 * abs(sin(phase * .pi + Double(index)))
    }
}

private extension MessageStatus {
    var label: String {
        switch self {
        case .sending: "Sending…"
        case .sent: "Sent"
        case .delivered: "Delivered"
        case .read: "Read"
        }
    }
}
