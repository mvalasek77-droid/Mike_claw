import SwiftUI

/// Add and arrange free-floating text annotations and stickers on the canvas.
/// Position and size are driven by sliders (in normalized canvas space) so the
/// result is pixel-identical at every export resolution.
struct OverlayPanel: View {
    @Binding var project: ScreenshotProject
    @State private var selected: UUID?

    private var overlays: [CanvasOverlay] { project.style.overlays }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addText
            stickers
            if !overlays.isEmpty { onCanvas }
            if let id = selected, overlays.contains(where: { $0.id == id }) {
                editor(for: id)
            }
        }
    }

    // MARK: Add controls

    private var addText: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Text")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    addChip(label: "Add text", systemImage: "plus") {
                        add(.text("Text"))
                    }
                    ForEach(CanvasOverlay.textPresets, id: \.self) { preset in
                        Button {
                            add(.text(preset))
                        } label: {
                            Text(preset)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.white.opacity(0.07), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var stickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Stickers")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(CanvasOverlay.stickerPalette.enumerated()), id: \.offset) { _, item in
                        Button {
                            add(.sticker(item.glyph, isSymbol: item.isSymbol))
                        } label: {
                            Group {
                                if item.isSymbol {
                                    Image(systemName: item.glyph)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                                } else {
                                    Text(item.glyph).font(.system(size: 22))
                                }
                            }
                            .frame(width: 46, height: 46)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add sticker")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Existing overlays

    private var onCanvas: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("On canvas")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(overlays) { overlay in
                        let isSelected = overlay.id == selected
                        Button {
                            Motion.run(Motion.snap) { selected = overlay.id }
                            Haptics.selection()
                        } label: {
                            HStack(spacing: 6) {
                                chipLabel(for: overlay)
                                Button {
                                    remove(overlay.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                                        .frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove overlay")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(.white.opacity(isSelected ? 0.12 : 0.05), in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)),
                                                       lineWidth: isSelected ? 2 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder
    private func chipLabel(for overlay: CanvasOverlay) -> some View {
        if overlay.kind == .sticker, overlay.isSymbol {
            Image(systemName: overlay.content).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        } else {
            Text(overlay.content.isEmpty ? "Text" : overlay.content)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .lineLimit(1)
        }
    }

    // MARK: Editor

    @ViewBuilder
    private func editor(for id: UUID) -> some View {
        let overlay = binding(for: id)
        Divider().overlay(.white.opacity(0.1))
        VStack(alignment: .leading, spacing: 14) {
            if overlay.wrappedValue.kind == .text {
                TextField("Text", text: overlay.content)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }

            SliderRow(label: "Size", value: overlay.sizeFraction, range: 0.03...0.4)
            SliderRow(label: "Horizontal", value: overlay.x, range: 0...1)
            SliderRow(label: "Vertical", value: overlay.y, range: 0...1)
            SliderRow(label: "Rotation", value: overlay.rotation, range: -180...180,
                      format: { String(format: "%.0f°", $0) })

            if overlay.wrappedValue.kind == .text {
                GlassSegmented(
                    options: CaptionStyle.FontWeightToken.allCases.map { ($0, $0.label) },
                    selection: overlay.weight
                )
            }

            if !(overlay.wrappedValue.kind == .sticker && !overlay.wrappedValue.isSymbol) {
                // Emoji stickers ignore tint; everything else can be colored.
                ColorPicker("Color", selection: colorBinding(overlay), supportsOpacity: true)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }

            Button(role: .destructive) {
                remove(id)
            } label: {
                Label("Delete overlay", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.warning)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
    }

    private func addChip(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(LiquidGlass.auroraGradient.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func add(_ overlay: CanvasOverlay) {
        project.style.overlays.append(overlay)
        selected = overlay.id
        Haptics.success()
    }

    private func remove(_ id: UUID) {
        project.style.overlays.removeAll { $0.id == id }
        if selected == id { selected = nil }
        Haptics.warning()
    }

    private func binding(for id: UUID) -> Binding<CanvasOverlay> {
        Binding(
            get: { project.style.overlays.first(where: { $0.id == id }) ?? CanvasOverlay() },
            set: { newValue in
                if let i = project.style.overlays.firstIndex(where: { $0.id == id }) {
                    project.style.overlays[i] = newValue
                }
            }
        )
    }

    private func colorBinding(_ overlay: Binding<CanvasOverlay>) -> Binding<Color> {
        Binding(
            get: { overlay.wrappedValue.color.color },
            set: { newValue in
                let ui = UIColor(newValue)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                overlay.wrappedValue.color = RGBAColor(red: r, green: g, blue: b, alpha: a)
            }
        )
    }
}
