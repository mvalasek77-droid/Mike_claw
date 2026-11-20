import PhotosUI
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
                HStack(spacing: Tokens.Spacing.md) {
                    UserAvatar(user: Session.me, size: 44)
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text(Session.me.displayName)
                            .font(.subheadline.weight(.semibold))
                        targetPicker
                    }
                }

                if model.target != nil {
                    TextField("Title (optional)", text: $model.title)
                        .font(Tokens.Typography.headline)
                }

                TextField("What's on your mind, \(Session.me.displayName)?",
                          text: $model.body, axis: .vertical)
                    .font(model.photo == nil ? .title3 : Tokens.Typography.body)
                    .lineLimit(4...14)
                    .focused($bodyFocused)

                if let photo = model.photo {
                    photoPreview(photo)
                } else if model.isLoadingPhoto {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .background(Tokens.Color.inputBackground,
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
                }

                if case .failed(let message) = model.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(Tokens.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) { addToPostBar }
        .onChange(of: model.photoSelection) {
            Task { await model.loadPhoto() }
        }
        .onAppear { bodyFocused = true }
    }

    private func photoPreview(_ photo: UIImage) -> some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { model.removePhoto() } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .padding(Tokens.Spacing.sm)
                .accessibilityLabel("Remove photo")
            }
    }

    /// Facebook's "Add to your post" tray, pinned above the keyboard.
    private var addToPostBar: some View {
        HStack {
            Text("Add to your post")
                .font(.subheadline.weight(.semibold))
            Spacer()
            PhotosPicker(selection: $model.photoSelection, matching: .images) {
                Label(model.photo == nil ? "Photo" : "Change photo",
                      systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .accessibilityLabel(model.photo == nil ? "Add a photo" : "Change photo")
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.md)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
            HStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: model.target == nil ? "globe.americas.fill" : "person.3.fill")
                Text(model.target?.name ?? "Your feed")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.accent)
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, Tokens.Spacing.xs)
            .background(Tokens.Color.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
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
