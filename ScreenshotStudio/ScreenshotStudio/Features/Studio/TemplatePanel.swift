import SwiftUI

/// One-tap professional layouts. Applying a template keeps the user's captions,
/// screenshots, status-bar settings and overlays — it only restyles the look.
struct TemplatePanel: View {
    @Binding var project: ScreenshotProject

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap a template to restyle this set. Your captions, screenshots and overlays are kept.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(StyleTemplate.all) { template in
                    Button {
                        apply(template)
                    } label: {
                        TemplateSwatch(template: template, isActive: isActive(template))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(template.name) template")
                }
            }
        }
    }

    /// A loose match: highlight a template whose defining look matches the
    /// current style, so the user sees which one (if any) is in effect.
    private func isActive(_ t: StyleTemplate) -> Bool {
        project.style.background.id == t.style.background.id &&
        project.style.caption.placement == t.style.caption.placement &&
        project.style.deviceFramed == t.style.deviceFramed &&
        project.style.adjustments == t.style.adjustments
    }

    private func apply(_ t: StyleTemplate) {
        Motion.run(Motion.snap) {
            var s = t.style
            // Preserve the user's content and preferences; restyle the rest.
            s.caption.text = project.style.caption.text
            s.caption.localized = project.style.caption.localized
            s.statusBar = project.style.statusBar
            s.overlays = project.style.overlays
            project.style = s
        }
        Haptics.success()
    }
}

/// A compact, true-to-style preview of a template: the backdrop, a stand-in
/// device, and a caption bar placed where the template puts it.
struct TemplateSwatch: View {
    let template: StyleTemplate
    var isActive: Bool = false

    private var style: CanvasStyle { template.style }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.background.shapeStyle)

                VStack(spacing: 5) {
                    if style.caption.placement == .top { captionBar }
                    deviceMock
                    if style.caption.placement == .bottom { captionBar }
                }
                .padding(10)
            }
            .frame(height: 108)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.15)),
                                  lineWidth: isActive ? 2.5 : 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 5, y: 3)

            Text(template.name)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(isActive ? 0.95 : 0.6))
        }
    }

    private var deviceMock: some View {
        RoundedRectangle(cornerRadius: style.deviceFramed ? 7 : 4, style: .continuous)
            .fill(Color.black.opacity(style.deviceFramed ? 0.75 : 0.35))
            .overlay(
                RoundedRectangle(cornerRadius: style.deviceFramed ? 7 : 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )
            .frame(width: 36, height: 62)
            .shadow(color: style.shadow ? .black.opacity(0.4) : .clear, radius: 4, y: 2)
    }

    private var captionBar: some View {
        VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill((style.caption.customColor?.color ?? .white).opacity(0.9))
                    .frame(width: i == 0 ? 46 : 30, height: 4)
            }
        }
    }
}
