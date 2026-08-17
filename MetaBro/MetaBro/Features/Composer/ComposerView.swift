import SwiftUI

/// Create a post — to a Bro-hood or your own feed. Title is optional (social
/// posts often skip it); body is required.
struct ComposerView: View {
    @State private var model: ComposerViewModel
    @FocusState private var bodyFocused: Bool

    init(feedService: FeedService, communityService: CommunityService) {
        _model = State(initialValue: ComposerViewModel(
            feedService: feedService, communityService: communityService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.phase == .posted {
                    successState
                } else {
                    editor
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        bodyFocused = false
                        Task { await model.submit() }
                    } label: {
                        if model.phase == .submitting {
                            ProgressView()
                        } else {
                            Text("Post").fontWeight(.bold)
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
        }
        .task { await model.loadTargets() }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                targetPicker

                if model.target != nil {
                    TextField("Title (optional)", text: $model.title)
                        .font(Tokens.Typography.headline)
                        .padding(Tokens.Spacing.md)
                        .liquidGlass(radius: Tokens.Radius.md)
                }

                TextField("What's on your mind, bro?", text: $model.body, axis: .vertical)
                    .lineLimit(6...14)
                    .focused($bodyFocused)
                    .padding(Tokens.Spacing.md)
                    .liquidGlass(radius: Tokens.Radius.md)

                if case .failed(let message) = model.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(Tokens.Spacing.lg)
        }
        .onAppear { bodyFocused = true }
    }

    private var targetPicker: some View {
        Menu {
            Button { model.target = nil } label: {
                Label("Your feed", systemImage: "person.crop.circle")
            }
            ForEach(model.targets) { community in
                Button { model.target = community } label: {
                    Label(community.name, systemImage: "person.3.fill")
                }
            }
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: model.target == nil ? "person.crop.circle" : "person.3.fill")
                Text(model.target?.name ?? "Your feed")
                    .font(Tokens.Typography.headline)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.sm)
            .liquidGlass(radius: Tokens.Radius.pill)
        }
        .accessibilityLabel("Post destination")
        .accessibilityValue(model.target?.name ?? "Your feed")
    }

    private var successState: some View {
        ContentUnavailableView {
            Label("Posted!", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Your post is live. Pull to refresh your feed to see it.")
        } actions: {
            Button("Write another") { model.reset(); bodyFocused = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
