import SwiftUI

/// Full-screen story viewer with segmented progress bars, 5s auto-advance,
/// and tap zones (left = previous, right = next). Marks each story seen on view.
struct StoryViewerView: View {
    let stories: [Story]
    @State var index: Int
    let onSeen: (UUID) -> Void
    let onClose: () -> Void

    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: TimeInterval = 5

    var body: some View {
        ZStack {
            background
            VStack(spacing: Tokens.Spacing.md) {
                progressBars
                header
                Spacer()
                Text(currentStory.caption)
                    .font(Tokens.Typography.title)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(Tokens.Spacing.xl)
                Spacer()
                Spacer()
            }
            .padding(Tokens.Spacing.lg)

            tapZones
        }
        .task(id: index) { await runSegment() }
    }

    private var currentStory: Story { stories[index] }

    private var background: some View {
        LinearGradient(colors: StoryPalette.gradient(currentStory.accentIndex),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white)
                                .frame(width: geo.size.width * fill(for: i))
                        }
                }
                .frame(height: 3)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                .overlay(Text(String(currentStory.author.displayName.prefix(1))).bold())
            Text(currentStory.author.displayName).font(Tokens.Typography.headline)
                .foregroundStyle(.white)
            Text(currentStory.createdAt.relative).font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
            }
            .accessibilityLabel("Close stories")
        }
    }

    /// Invisible left/right tap targets for manual navigation.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { goBack() }
            Color.clear.contentShape(Rectangle()).onTapGesture { advance() }
        }
        .ignoresSafeArea()
    }

    private func fill(for i: Int) -> Double {
        if i < index { return 1 }
        if i > index { return 0 }
        return progress
    }

    private func runSegment() async {
        onSeen(currentStory.id)
        progress = 0
        // Reduce Motion: hold the story without an animated bar; user taps on.
        guard !reduceMotion else { progress = 1; return }
        let steps = 50
        let step = duration / Double(steps)
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            if Task.isCancelled { return }
            progress = min(1, progress + 1.0 / Double(steps))
        }
        advance()
    }

    private func advance() {
        if index < stories.count - 1 { index += 1 } else { onClose() }
    }

    private func goBack() {
        if index > 0 { index -= 1 } else { progress = 0 }
    }
}
