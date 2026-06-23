import SwiftUI

/// The editor's live preview with **draggable overlays**. Overlay handles can
/// be dragged directly on the canvas to reposition text and stickers; touches
/// that miss a handle fall through, so the slide pager and other gestures keep
/// working. The Overlays panel sliders remain as a precise fallback.
///
/// Overlay positions are normalized (0…1) over the full canvas, and the canvas
/// fills this view exactly (same aspect ratio), so a touch in this view maps
/// straight to a normalized position.
struct InteractiveCanvasPreview: View {
    @Binding var project: ScreenshotProject
    let slide: Slide?

    private static let space = "interactiveCanvas"

    private var canvasSize: CGSize { project.deviceSize.pixelSize(for: project.orientation) }
    private var aspect: CGFloat { canvasSize.height == 0 ? 1 : canvasSize.width / canvasSize.height }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CanvasPreview(project: project, slide: slide)
                ForEach(project.style.overlays) { overlay in
                    handle(for: overlay, in: geo.size)
                }
            }
            .coordinateSpace(name: Self.space)
        }
        .aspectRatio(aspect, contentMode: .fit)
    }

    private func handle(for overlay: CanvasOverlay, in size: CGSize) -> some View {
        // A grab area roughly the overlay's footprint, never smaller than a
        // comfortable touch target.
        let side = max(overlay.sizeFraction * size.width * 1.5, 44)
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(LiquidGlass.accent.opacity(0.55),
                          style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .position(x: overlay.x * size.width, y: overlay.y * size.height)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard let index = project.style.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
                        project.style.overlays[index].x = min(max(value.location.x / size.width, 0), 1)
                        project.style.overlays[index].y = min(max(value.location.y / size.height, 0), 1)
                    }
                    .onEnded { _ in Haptics.selection() }
            )
            .accessibilityLabel("Drag “\(overlay.content)” overlay")
    }
}
