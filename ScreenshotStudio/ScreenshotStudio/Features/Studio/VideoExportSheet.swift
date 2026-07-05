import SwiftUI
import AVFoundation

/// Drives an App Preview video export: renders the studio backplate, composites
/// the picked video into the device screen, and saves the result to Photos —
/// with honest progress.
struct VideoExportSheet: View {
    let sourceURL: URL
    let project: ScreenshotProject

    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case preparing
        case exporting(Double)
        case saving
        case done
        case failed(String)
    }

    @State private var phase: Phase = .preparing

    private var isBusy: Bool {
        switch phase {
        case .done, .failed: return false
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    statusCard
                    actions
                }
                .padding(24)
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationTitle("App Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isBusy)
        .task { await run() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundStyle(LiquidGlass.auroraGradient)
            Text("Styled App Preview")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                switch phase {
                case .preparing:
                    ProgressView().tint(LiquidGlass.accent)
                    label("Preparing the frame…")
                case .exporting(let p):
                    ProgressView(value: p).tint(LiquidGlass.accent)
                    label("Compositing video… \(Int(p * 100))%")
                case .saving:
                    ProgressView().tint(LiquidGlass.accent)
                    label("Saving to Photos…")
                case .done:
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44)).foregroundStyle(LiquidGlass.success)
                    label("Saved to your “Shipshot” album in Photos.")
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38)).foregroundStyle(LiquidGlass.warning)
                    label(message)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actions: some View {
        switch phase {
        case .done:
            PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        case .failed:
            PrimaryButton(title: "Close", style: .glass) { dismiss() }
        default:
            EmptyView()
        }
    }

    @MainActor
    private func run() async {
        do {
            let canvasSize = project.deviceSize.pixelSize(for: project.orientation)
            let asset = AVURLAsset(url: sourceURL)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                phase = .failed("That file doesn't contain a video track.")
                return
            }
            let natural = try await track.load(.naturalSize)
            let preferred = try await track.load(.preferredTransform)
            let oriented = natural.applying(preferred)
            let videoPixels = CGSize(width: abs(oriented.width), height: abs(oriented.height))

            let profile = project.deviceSize.statusBarLayout.frameProfile
            let layout = ScreenshotComposer.layout(canvas: canvasSize,
                                                    style: project.style,
                                                    sourceSize: videoPixels,
                                                    profile: profile)

            let caption = project.slides.first.map { project.captionText(for: $0) }
                ?? project.style.caption.text
            let black = VideoExporter.blackImage(aspect: videoPixels)
            guard let backplate = ScreenshotRenderer.render(
                canvasSize: canvasSize,
                style: project.style,
                image: black,
                captionText: caption,
                statusBarLayout: project.deviceSize.statusBarLayout) else {
                phase = .failed("Couldn't render the studio frame.")
                return
            }

            phase = .exporting(0)
            let outputURL = try await VideoExporter.export(
                sourceURL: sourceURL,
                backplate: backplate,
                canvasSize: canvasSize,
                screenRect: layout.screenRect
            ) { value in
                Task { @MainActor in
                    if case .exporting = phase { phase = .exporting(value) }
                }
            }

            phase = .saving
            try await PhotoExporter.saveVideo(outputURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: sourceURL)
            phase = .done
            Haptics.success()
        } catch {
            BugLog.error("VideoExport", error.localizedDescription)
            phase = .failed(error.localizedDescription)
            Haptics.error()
        }
    }
}
