import SwiftUI

// MARK: - Layout

struct LayoutPanel: View {
    @Binding var project: ScreenshotProject

    var body: some View {
        VStack(spacing: 18) {
            GlassSegmented(
                options: CanvasOrientation.allCases.map { ($0, $0.label) },
                selection: $project.orientation
            )

            ToggleRow(label: "Device frame", systemImage: "iphone", isOn: $project.style.deviceFramed)
            ToggleRow(label: "Drop shadow", systemImage: "shadow", isOn: $project.style.shadow)

            SliderRow(label: "Margin", value: $project.style.marginFraction, range: 0...0.35)
            if project.style.deviceFramed {
                SliderRow(label: "Corner radius", value: $project.style.cornerFraction, range: 0...0.12)
            }
        }
    }
}

// MARK: - Background

struct BackgroundPanel: View {
    @Binding var project: ScreenshotProject

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BackgroundStyle.presets) { preset in
                        let isSelected = preset.id == project.style.background.id
                        Button {
                            Motion.run(Motion.snap) {
                                // Keep the user's custom angle when switching.
                                var next = preset
                                next.angle = project.style.background.angle
                                project.style.background = next
                            }
                            Haptics.selection()
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(preset.shapeStyle)
                                    .frame(width: 58, height: 84)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.18)),
                                                          lineWidth: isSelected ? 3 : 1)
                                    )
                                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(isSelected ? 0.95 : 0.55))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.name) background")
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 2)
            }

            if project.style.background.kind == .gradient {
                SliderRow(label: "Gradient angle", value: $project.style.background.angle,
                          range: 0...360, format: { String(format: "%.0f°", $0) })
            }
        }
    }
}

// MARK: - Caption

struct CaptionPanel: View {
    @Binding var project: ScreenshotProject

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { project.style.caption.customColor?.color ?? .white },
            set: { newValue in
                let ui = UIColor(newValue)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                project.style.caption.customColor = RGBAColor(red: r, green: g, blue: b, alpha: a)
            }
        )
    }

    private var usesCustomColor: Binding<Bool> {
        Binding(
            get: { project.style.caption.customColor != nil },
            set: { project.style.caption.customColor = $0 ? RGBAColor.white : nil }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Marketing headline", text: $project.style.caption.text, axis: .vertical)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .lineLimit(1...3)
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))

            GlassSegmented(
                options: CaptionPlacement.allCases.map { ($0, $0.label) },
                selection: $project.style.caption.placement
            )

            if project.style.caption.placement != .none {
                SliderRow(label: "Text size", value: $project.style.caption.sizeFraction, range: 0.04...0.12)
                SliderRow(label: "Band height", value: $project.style.caption.heightFraction, range: 0.08...0.4)

                GlassSegmented(
                    options: CaptionStyle.FontWeightToken.allCases.map { ($0, $0.label) },
                    selection: $project.style.caption.weight
                )

                ToggleRow(label: "Custom text color", systemImage: "paintpalette", isOn: usesCustomColor)
                if project.style.caption.customColor != nil {
                    ColorPicker("Text color", selection: customColorBinding, supportsOpacity: false)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
            }
        }
    }
}

// MARK: - Device sizes

struct DevicePanel: View {
    @Binding var project: ScreenshotProject

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Primary size")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))

            ForEach(ASCDeviceSize.catalog) { size in
                deviceRow(size)
            }
        }
    }

    @ViewBuilder
    private func deviceRow(_ size: ASCDeviceSize) -> some View {
        let isPrimary = size.id == project.deviceSizeID
        let isExtra = project.additionalSizeIDs.contains(size.id)

        // Two sibling tap targets (never nested): the row selects the primary
        // size; the trailing control toggles "also export this size".
        HStack(spacing: 12) {
            Button {
                Motion.run(Motion.snap) { project.deviceSizeID = size.id }
                project.additionalSizeIDs.removeAll { $0 == size.id }
                Haptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: size.family.symbol)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isPrimary ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(LiquidGlass.primaryText.opacity(0.5)))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(size.displayName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            if size.isRequired {
                                Text("Required")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(LiquidGlass.success.opacity(0.85), in: Capsule())
                            }
                        }
                        Text(size.resolutionLabel(for: project.orientation))
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isPrimary ? "Primary export size" : "Tap to make primary")

            if isPrimary {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LiquidGlass.accent)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
            } else {
                Button {
                    if isExtra { project.additionalSizeIDs.removeAll { $0 == size.id } }
                    else { project.additionalSizeIDs.append(size.id) }
                    Haptics.selection()
                } label: {
                    Image(systemName: isExtra ? "plus.circle.fill" : "plus.circle")
                        .foregroundStyle(isExtra ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.4))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExtra ? "Remove \(size.displayName) from export" : "Also export \(size.displayName)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
