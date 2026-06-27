import SwiftUI

/// Post detail: the original post on a Liquid Glass card, followed by its
/// threaded comments, with an inline reply composer pinned to the bottom.
struct PostDetailView: View {
    @State private var model: PostDetailViewModel
    @State private var replyText = ""
    @State private var replyingTo: Comment?
    @FocusState private var composerFocused: Bool
    let safetyService: SafetyService

    init(post: Post, service: CommentService, safetyService: SafetyService,
         moderationService: ModerationService) {
        _model = State(initialValue: PostDetailViewModel(post: post, service: service,
                                                          moderationService: moderationService))
        self.safetyService = safetyService
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Tokens.Spacing.lg) {
                    PostCardView(post: model.post, onVote: { _ in }, safetyService: safetyService)
                    Divider().overlay(Tokens.Color.separator)
                    threadContent
                }
                .padding(Tokens.Spacing.lg)
            }
            if model.post.isLocked {
                lockedNotice
            } else {
                composer
            }
        }
        .navigationTitle("Discussion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canModerate {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await model.togglePin() } } label: {
                            Label(model.post.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                        }
                        Button { Task { await model.toggleLock() } } label: {
                            Label(model.post.isLocked ? "Unlock" : "Lock", systemImage: "lock")
                        }
                    } label: {
                        Image(systemName: "shield")
                    }
                    .accessibilityLabel("Mod actions")
                }
            }
        }
        .task { await model.load() }
    }

    private var lockedNotice: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "lock.fill")
            Text("This thread is locked. No new comments.")
                .font(Tokens.Typography.caption)
        }
        .foregroundStyle(Tokens.Color.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(Tokens.Spacing.md)
        .background(.bar)
    }

    @ViewBuilder
    private var threadContent: some View {
        switch model.state {
        case .loading:
            ProgressView().padding(.top, Tokens.Spacing.xl)
        case .empty:
            ContentUnavailableView("No comments yet",
                                   systemImage: "bubble.left",
                                   description: Text("Be the first bro to weigh in."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            LazyVStack(spacing: Tokens.Spacing.md) {
                ForEach(model.visible) { item in
                    CommentRowView(
                        item: item,
                        isCollapsed: model.isCollapsed(item.id),
                        onVote: { value in Task { await model.vote(on: item.comment, value: value) } },
                        onToggleCollapse: {
                            withAnimation(Tokens.Motion.snappy) { model.toggleCollapse(item.id) }
                        },
                        onReply: { startReply(to: item.comment) },
                        safetyService: safetyService
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Tokens.Motion.gentle, value: model.visible)
        }
    }

    private var composer: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            if let replyingTo {
                HStack {
                    Text("Replying to \(replyingTo.author.handle)")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textSecondary)
                    Spacer()
                    Button { self.replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Cancel reply")
                }
            }
            HStack(spacing: Tokens.Spacing.sm) {
                TextField("Add to the discussion…", text: $replyText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(Tokens.Spacing.md)
                    .liquidGlass(radius: Tokens.Radius.lg)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(trimmed.isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(Tokens.Spacing.md)
        .background(.bar)
    }

    private var trimmed: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startReply(to comment: Comment) {
        replyingTo = comment
        composerFocused = true
    }

    private func send() {
        let body = trimmed
        guard !body.isEmpty else { return }
        let parent = replyingTo?.id
        replyText = ""
        replyingTo = nil
        composerFocused = false
        Task { await model.reply(to: parent, body: body) }
    }
}
