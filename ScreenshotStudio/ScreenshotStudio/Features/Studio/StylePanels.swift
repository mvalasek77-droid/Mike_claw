import SwiftUI

// MARK: - Layout

struct LayoutPanel: View {
    @Binding var project: ScreenshotProject

    private var batteryBinding: Binding<Double> {
        Binding(get: { Double(project.style.statusBar.batteryPercent) },
                set: { project.style.statusBar.batteryPercent = Int($0.rounded()) })
    }

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

            Divider().overlay(.white.opacity(0.1))

            ToggleRow(label: "Clean status bar", systemImage: "clock.fill",
                      isOn: $project.style.statusBar.enabled)
            if project.style.statusBar.enabled {
                statusBarControls
            }
        }
    }

    @ViewBuilder
    private var statusBarControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Time")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Spacer()
                TextField("9:41", text: $project.style.statusBar.time)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(LiquidGlass.primaryText)
                    .frame(maxWidth: 110)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            GlassSegmented(
                options: StatusBarStyle.GlyphAppearance.allCases.map { ($0, $0.label) },
                selection: $project.style.statusBar.appearance
            )

            ToggleRow(label: "Cellular", systemImage: "cellularbars", isOn: $project.style.statusBar.showCellular)
            ToggleRow(label: "Wi-Fi", systemImage: "wifi", isOn: $project.style.statusBar.showWiFi)
            ToggleRow(label: "Battery %", systemImage: "battery.100", isOn: $project.style.statusBar.showBatteryPercent)
            SliderRow(label: "Battery", value: batteryBinding, range: 0...100,
                      format: { String(format: "%.0f%%", $0) })

            ToggleRow(label: "Carrier name", systemImage: "antenna.radiowaves.left.and.right",
                      isOn: $project.style.statusBar.showCarrier)
            if project.style.statusBar.showCarrier {
                TextField("Carrier", text: $project.style.statusBar.carrier)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Enhance (color "pop")

struct EnhancePanel: View {
    @Binding var project: ScreenshotProject

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(EnhancePreset.all) { preset in
                        let isSelected = project.style.adjustments == preset.adjustments
                        Button {
                            Motion.run(Motion.snap) { project.style.adjustments = preset.adjustments }
                            Haptics.selection()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(LiquidGlass.primaryText.opacity(0.6)))
                                    .frame(width: 56, height: 48)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)),
                                                          lineWidth: isSelected ? 2 : 1)
                                    )
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(isSelected ? 0.95 : 0.55))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.name) enhancement")
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 2)
            }

            SliderRow(label: "Brightness", value: $project.style.adjustments.brightness, range: -0.25...0.25,
                      format: { String(format: "%+.0f", $0 * 400) })
            SliderRow(label: "Contrast", value: $project.style.adjustments.contrast, range: 0.6...1.5,
                      format: { String(format: "%.0f%%", $0 * 100) })
            SliderRow(label: "Saturation", value: $project.style.adjustments.saturation, range: 0...2,
                      format: { String(format: "%.0f%%", $0 * 100) })
            SliderRow(label: "Warmth", value: $project.style.adjustments.warmth, range: -1...1,
                      format: { String(format: "%+.0f", $0 * 100) })

            Button {
                Motion.run(Motion.snap) { project.style.adjustments = ImageAdjustments() }
                Haptics.selection()
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
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
    /// The slide currently shown in the editor, so we can offer a per-slide
    /// caption override. `nil` when the set has no slides.
    var slideIndex: Int? = nil

    @State private var pendingRemoval: String?

    private var isPrimaryLanguage: Bool { project.activeLanguage == project.primaryLanguage }

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

    /// Headline for the active language: primary lives in `text`, others in
    /// the localized dictionary.
    private var headlineBinding: Binding<String> {
        Binding(
            get: {
                isPrimaryLanguage ? project.style.caption.text
                                  : (project.style.caption.localized[project.activeLanguage] ?? "")
            },
            set: { newValue in
                if isPrimaryLanguage {
                    project.style.caption.text = newValue
                } else {
                    project.style.caption.localized[project.activeLanguage] = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            languageBar

            TextField("Marketing headline", text: headlineBinding, axis: .vertical)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .lineLimit(1...3)
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))

            perSlideOverride

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

    // MARK: Localization

    private var addableLanguages: [ASCLanguage] {
        ASCLanguage.catalog.filter { !project.languages.contains($0.code) }
    }

    private var languageBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(project.languages, id: \.self) { code in
                        languageChip(code)
                    }
                    Menu {
                        ForEach(addableLanguages) { lang in
                            Button(lang.name) { addLanguage(lang.code) }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .disabled(addableLanguages.isEmpty)
                }
                .padding(.horizontal, 2)
            }

            if project.languages.count > 1 {
                Text("Editing \(ASCLanguage.displayName(for: project.activeLanguage)). Each language exports its own caption set.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove \(ASCLanguage.displayName(for: $0))?" } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove language and its captions", role: .destructive) {
                if let code = pendingRemoval { removeLanguage(code) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This language has captions that will be deleted.")
        }
    }

    private func languageChip(_ code: String) -> some View {
        let isSelected = code == project.activeLanguage
        let isPrimary = code == project.primaryLanguage
        return Button {
            Motion.run(Motion.snap) { project.activeLanguage = code }
            Haptics.selection()
        } label: {
            HStack(spacing: 5) {
                Text(code)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if isPrimary {
                    Image(systemName: "star.fill").font(.system(size: 8))
                }
            }
            .foregroundStyle(isSelected ? .white : LiquidGlass.primaryText.opacity(0.7))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Group {
                    if isSelected { Capsule().fill(LiquidGlass.auroraGradient.opacity(0.9)) }
                    else { Capsule().fill(.white.opacity(0.06)) }
                }
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isPrimary {
                Button(role: .destructive) { requestRemoveLanguage(code) } label: {
                    Label("Remove \(ASCLanguage.displayName(for: code))", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel("\(ASCLanguage.displayName(for: code))\(isPrimary ? ", primary" : "")")
    }

    @ViewBuilder
    private var perSlideOverride: some View {
        if let index = slideIndex, project.slides.indices.contains(index) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This screenshot's caption")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                TextField("Use shared headline", text: overrideBinding(index), axis: .vertical)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                Text("Leave empty to use the shared headline above.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
            }
        }
    }

    private func overrideBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard project.slides.indices.contains(index) else { return "" }
                let slide = project.slides[index]
                return isPrimaryLanguage ? (slide.captionOverride ?? "")
                                         : (slide.localizedOverrides[project.activeLanguage] ?? "")
            },
            set: { newValue in
                guard project.slides.indices.contains(index) else { return }
                let value: String? = newValue.isEmpty ? nil : newValue
                if isPrimaryLanguage {
                    project.slides[index].captionOverride = value
                } else {
                    project.slides[index].localizedOverrides[project.activeLanguage] = value
                }
            }
        )
    }

    private func addLanguage(_ code: String) {
        guard !project.languages.contains(code) else { return }
        project.languages.append(code)
        project.activeLanguage = code
        Haptics.success()
    }

    /// Whether a language has any captions that would be lost on removal.
    private func languageHasCaptions(_ code: String) -> Bool {
        if let headline = project.style.caption.localized[code], !headline.isEmpty { return true }
        return project.slides.contains { ($0.localizedOverrides[code]?.isEmpty == false) }
    }

    private func requestRemoveLanguage(_ code: String) {
        if languageHasCaptions(code) {
            pendingRemoval = code
        } else {
            removeLanguage(code)
        }
    }

    private func removeLanguage(_ code: String) {
        guard code != project.primaryLanguage else { return }
        project.languages.removeAll { $0 == code }
        project.style.caption.localized[code] = nil
        for i in project.slides.indices {
            project.slides[i].localizedOverrides[code] = nil
        }
        if project.activeLanguage == code { project.activeLanguage = project.primaryLanguage }
        Haptics.warning()
    }
}

// MARK: - Device sizes

struct DevicePanel: View {
    @Binding var project: ScreenshotProject

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tap a size to make it primary, or + to also export it. The 6.9\" iPhone and 13\" iPad sets are what App Store Connect requires.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            familySection("iPhone", symbol: "iphone", family: .iPhone)
            familySection("iPad", symbol: "ipad", family: .iPad)
        }
    }

    @ViewBuilder
    private func familySection(_ title: String, symbol: String, family: DeviceFamily) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            .padding(.bottom, 2)

            ForEach(ASCDeviceSize.catalog.filter { $0.family == family }) { size in
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
