import SwiftUI

/// Renders one composed screenshot at its exact pixel size.
///
/// The view is laid out in *pixel-points* (its frame equals the target
/// resolution), so feeding it to an `ImageRenderer` at `scale = 1` yields an
/// image whose pixel dimensions match the App Store Connect slot precisely.
/// For on-screen preview, callers wrap it in `.scaleEffect` to fit the
/// device. Because the same view backs both paths, what you see is exactly
/// what exports.
struct ScreenshotCanvas: View {
    let canvasSize: CGSize
    let style: CanvasStyle
    let image: UIImage?
    let captionText: String
    /// Status-bar layout for the target device class. Defaults to a modern
    /// iPhone so callers that don't care still render sensibly.
    var statusBarLayout: StatusBarLayoutKind = .dynamicIsland

    private var sourcePixelSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.size.width * image.scale,
                      height: image.size.height * image.scale)
    }

    private var layout: ComposedLayout {
        ScreenshotComposer.layout(canvas: canvasSize,
                                  style: style,
                                  sourceSize: sourcePixelSize,
                                  profile: statusBarLayout.frameProfile)
    }

    var body: some View {
        let l = layout
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(style.background.shapeStyle)
                .frame(width: canvasSize.width, height: canvasSize.height)

            if let captionRect = l.captionRect, style.caption.placement != .none {
                caption(in: l)
                    .frame(width: captionRect.width, height: captionRect.height)
                    .offset(x: captionRect.minX, y: captionRect.minY)
            }

            device(in: l)
                .frame(width: l.deviceRect.width, height: l.deviceRect.height)
                .offset(x: l.deviceRect.minX, y: l.deviceRect.minY)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }

    // MARK: Caption

    private var captionColor: Color {
        if let custom = style.caption.customColor { return custom.color }
        // Auto-contrast against the background.
        return style.background.averageLuminance > 0.5 ? Color(white: 0.07) : .white
    }

    @ViewBuilder
    private func caption(in l: ComposedLayout) -> some View {
        Text(captionText.isEmpty ? " " : captionText)
            .font(.system(size: l.captionFontSize,
                          weight: style.caption.weight.swiftUIWeight,
                          design: .rounded))
            .foregroundStyle(captionColor)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, canvasSize.width * 0.08)
    }

    // MARK: Device

    @ViewBuilder
    private func device(in l: ComposedLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if style.deviceFramed {
                RoundedRectangle(cornerRadius: l.cornerRadius + l.bezelWidth, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: l.cornerRadius + l.bezelWidth, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: max(l.bezelWidth * 0.18, 1)
                            )
                    )
                    .frame(width: l.deviceRect.width, height: l.deviceRect.height)
            }

            screenshotLayer(in: l)
                .frame(width: l.screenRect.width, height: l.screenRect.height)
                .clipShape(RoundedRectangle(cornerRadius: l.cornerRadius, style: .continuous))
                .offset(x: l.bezelWidth, y: l.bezelWidth)
        }
        .frame(width: l.deviceRect.width, height: l.deviceRect.height)
        .shadow(color: style.shadow ? .black.opacity(0.35) : .clear,
                radius: style.shadow ? canvasSize.width * 0.04 : 0,
                x: 0, y: canvasSize.width * 0.012)
    }

    /// Apply the "pop" color adjustments. These are SwiftUI color filters, so
    /// the exact look is preserved through `ImageRenderer` on export.
    @ViewBuilder
    private func adjusted(_ content: some View) -> some View {
        let adj = style.adjustments
        content
            .saturation(adj.clampedSaturation)
            .contrast(adj.clampedContrast)
            .brightness(adj.clampedBrightness)
            .colorMultiply(adj.warmthTint)
    }

    @ViewBuilder
    private func screenshotLayer(in l: ComposedLayout) -> some View {
        if let image {
            adjusted(Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: l.screenRect.width, height: l.screenRect.height))
                .overlay(alignment: .top) {
                    if style.statusBar.enabled {
                        StatusBarOverlay(kind: statusBarLayout,
                                         style: style.statusBar,
                                         width: l.screenRect.width)
                    }
                }
        } else {
            // Empty-slide placeholder — still looks intentional in preview.
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: l.screenRect.width * 0.04) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: l.screenRect.width * 0.16, weight: .light))
                    Text("Add a screenshot")
                        .font(.system(size: l.screenRect.width * 0.05, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
