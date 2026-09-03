import SwiftUI

/// The "ask a person who's done this before" surface.
///
/// The step walkthroughs cover the happy path. This covers the moment
/// someone falls off it — a rejection email they don't understand, a
/// build that never appeared, a word nobody defined. It opens knowing
/// which step they're on and what's currently blocking them, so the
/// first answer is already about their situation rather than a generic
/// article.
struct ASCCoachChatView: View {
    @ObservedObject var chat: ASCCoachChat

    let step: ASCStep?
    let appName: String
    let bundleID: String
    let completed: Set<Int>
    let macPaired: Bool
    let blockingIssues: [String]
    let outstandingItems: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                VStack(spacing: 0) {
                    transcript
                    if let error = chat.lastError { errorBar(error) }
                    if !chat.suggestions.isEmpty && !chat.isThinking { suggestionRow }
                    inputBar
                }
            }
            .navigationTitle("Ask about submitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { chat.prepare(for: step) }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.turns.isEmpty { openingCard }
                    ForEach(chat.turns) { turn in
                        bubble(turn).id(turn.id)
                    }
                    if chat.isThinking { thinkingBubble.id("thinking") }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.turns.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.isThinking) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var openingCard: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(LiquidGlass.accent)
                        .accessibilityHidden(true)
                    Text(step.map { "Step \($0.number): \($0.title)" } ?? "App Store submission")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                Text("Ask me anything about getting \(appName.isEmpty ? "your app" : appName) onto the App Store. I know Apple's rules and I can see where you are, so answers are about your situation, not a generic article.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing here changes your app. I give advice; the buttons in the guide do the work.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private func bubble(_ turn: ASCCoachChat.Turn) -> some View {
        let isUser = turn.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(isUser ? 1 : 0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    isUser
                        ? AnyShapeStyle(LiquidGlass.accent.opacity(0.28))
                        : AnyShapeStyle(Color.white.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(isUser ? 0.2 : 0.1))
                )
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You asked" : "Coach"): \(turn.text)")
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().tint(LiquidGlass.primaryText).scaleEffect(0.8)
            Text("Thinking…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LiquidGlass.warning)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(LiquidGlass.warning.opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    // MARK: Suggestions

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.suggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.selection()
                        send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Asks the coach this question")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything about submitting…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14)))
                .accessibilityLabel("Your question")

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        canSend ? AnyShapeStyle(LiquidGlass.auroraGradient)
                                : AnyShapeStyle(Color.white.opacity(0.12)),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isThinking
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !chat.isThinking else { return }
        draft = ""
        inputFocused = false
        Task {
            await chat.ask(
                clean,
                step: step,
                appName: appName,
                bundleID: bundleID,
                completed: completed,
                macPaired: macPaired,
                blockingIssues: blockingIssues,
                outstandingItems: outstandingItems
            )
        }
    }
}
