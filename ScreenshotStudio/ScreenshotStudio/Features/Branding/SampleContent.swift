import SwiftUI

/// Seeds a single polished sample set on first launch so the gallery isn't
/// empty — it shows off framing, a backdrop and a caption, and the user can
/// edit or delete it freely. Runs at most once (guarded by a flag) and never
/// when the user already has sets.
@MainActor
enum SampleContent {
    private static let seededKey = "didSeedSampleSet.v1"

    static func seedIfNeeded(into store: ProjectStore) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)
        guard store.projects.isEmpty else { return }
        guard let image = makeMockScreenshot(), let file = ImageStore.save(image) else { return }

        var project = ScreenshotProject.newProject(name: "Welcome")
        if let template = StyleTemplate.all.first(where: { $0.id == "bold" }) {
            project.style = template.style
        }
        project.style.caption.text = "Your app, beautifully framed"
        let px = CGSize(width: image.size.width * image.scale,
                        height: image.size.height * image.scale)
        project.slides = [Slide(imageFile: file,
                                sourcePixelWidth: px.width,
                                sourcePixelHeight: px.height)]
        store.upsert(project)
        BugLog.info("Sample", "Seeded the Welcome sample set.")
    }

    /// Render a tasteful, generic "app screen" so the sample looks real without
    /// bundling any image asset.
    static func makeMockScreenshot() -> UIImage? {
        let size = CGSize(width: 1179, height: 2556)
        let renderer = ImageRenderer(content: MockScreen().frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// A purely cosmetic stand-in app screen, rendered once to a PNG.
private struct MockScreen: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.20),
                                    Color(red: 0.05, green: 0.06, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 40) {
                Spacer().frame(height: 150)

                Text("Good morning")
                    .font(.system(size: 68, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Here's your day at a glance")
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                VStack(spacing: 28) {
                    ForEach(0..<3, id: \.self) { _ in card }
                }
                .padding(.top, 16)

                Spacer()
            }
            .padding(.horizontal, 90)
        }
        .frame(width: 1179, height: 2556)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(.white.opacity(0.08))
            .frame(height: 230)
            .overlay(
                HStack(spacing: 30) {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.38, green: 0.46, blue: 1.0),
                                                      Color(red: 0.95, green: 0.39, blue: 0.73)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 116, height: 116)
                    VStack(alignment: .leading, spacing: 16) {
                        RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.85)).frame(width: 320, height: 28)
                        RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.35)).frame(width: 230, height: 22)
                    }
                    Spacer(minLength: 0)
                }
                .padding(44)
            )
    }
}
