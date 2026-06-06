import SwiftUI

/// The editor. A live, pixel-accurate preview sits above a tabbed panel of
/// styling controls; the toolbar drives renaming and export. Every edit
/// autosaves through the `ProjectStore`, so the user never thinks about
/// "saving" — it just persists.
struct StudioView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var project: ScreenshotProject
    @State private var currentSlide = 0
    @State private var panel: Panel = .layout
    @State private var showPhotoPicker = false
    @State private var showExport = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var saveTask: Task<Void, Never>?

    init(project: ScreenshotProject) {
        _project = State(initialValue: project)
    }

    enum Panel: String, CaseIterable, Identifiable {
        case layout = "Layout", background = "Backdrop", caption = "Caption", enhance = "Enhance", device = "Sizes"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .layout: return "square.resize"
            case .background: return "paintbrush.fill"
            case .caption: return "textformat"
            case .enhance: return "wand.and.stars"
            case .device: return "iphone.gen3"
            }
        }
    }

    private var selectedSlide: Slide? {
        guard project.slides.indices.contains(currentSlide) else { return project.slides.first }
        return project.slides[currentSlide]
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            previewSection
            filmstrip
            panelPicker
            ScrollView {
                panelContent
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
            }
        }
        .background(LiquidGlassBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityLabel("Close editor")
            }
            ToolbarItem(placement: .principal) {
                Button {
                    draftName = project.name
                    isRenaming = true
                } label: {
                    HStack(spacing: 5) {
                        Text(project.name)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    }
                }
                .accessibilityLabel("Set name, \(project.name). Double tap to rename.")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(project.slides.isEmpty)
                .accessibilityLabel("Export")
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { images in addImages(images) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(project: project)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .alert("Rename set", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { project.name = trimmed }
            }
        }
        // Persist edits, but debounce disk writes so dragging a slider doesn't
        // hammer the file system every frame. A final save fires on close.
        .onChange(of: project) { _, newValue in scheduleSave(newValue) }
        .onChange(of: project.slides.count) { _, count in
            currentSlide = min(currentSlide, max(0, count - 1))
        }
        .onDisappear {
            saveTask?.cancel()
            store.upsert(project)
        }
    }

    private func scheduleSave(_ snapshot: ScreenshotProject) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            store.upsert(snapshot)
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        Group {
            if project.slides.isEmpty {
                CanvasPreview(project: project, slide: nil)
                    .padding(.horizontal, 44)
                    .padding(.vertical, 10)
            } else {
                TabView(selection: $currentSlide) {
                    ForEach(Array(project.slides.enumerated()), id: \.element.id) { index, slide in
                        CanvasPreview(project: project, slide: slide)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 10)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .frame(maxHeight: 360)
        .animation(Motion.smooth, value: project.style)
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(project.slides.enumerated()), id: \.element.id) { index, slide in
                    let isSelected = index == currentSlide
                    Button {
                        Motion.run(Motion.snap) { currentSlide = index }
                        Haptics.selection()
                    } label: {
                        thumb(for: slide)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(isSelected ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.15)),
                                                  lineWidth: isSelected ? 2.5 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if index > 0 {
                            Button { move(from: index, to: index - 1) } label: { Label("Move left", systemImage: "arrow.left") }
                        }
                        if index < project.slides.count - 1 {
                            Button { move(from: index, to: index + 1) } label: { Label("Move right", systemImage: "arrow.right") }
                        }
                        Button(role: .destructive) { delete(slide) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .accessibilityLabel("Screenshot \(index + 1) of \(project.slides.count)")
                }

                Button {
                    Haptics.tap()
                    showPhotoPicker = true
                } label: {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(width: 46, height: 84)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(LiquidGlass.accent)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add screenshots")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .frame(height: 100)
    }

    private func thumb(for slide: Slide) -> some View {
        let image = ImageStore.load(slide.imageFile)
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(.black.opacity(0.3))
            .frame(width: 46, height: 84)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Panels

    private var panelPicker: some View {
        HStack(spacing: 6) {
            ForEach(Panel.allCases) { p in
                let isSelected = p == panel
                Button {
                    Motion.run(Motion.snap) { panel = p }
                    Haptics.selection()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.icon).font(.system(size: 15, weight: .semibold))
                        Text(p.rawValue).font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? .white : LiquidGlass.primaryText.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Group { if isSelected { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LiquidGlass.auroraGradient.opacity(0.85)) } }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.rawValue)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .layout:     LayoutPanel(project: $project)
        case .background: BackgroundPanel(project: $project)
        case .caption:    CaptionPanel(project: $project)
        case .enhance:    EnhancePanel(project: $project)
        case .device:     DevicePanel(project: $project)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            PrimaryButton(title: "Add", systemImage: "photo.badge.plus", style: .glass) {
                showPhotoPicker = true
            }
            .frame(maxWidth: 130)

            PrimaryButton(title: "Export", systemImage: "square.and.arrow.up",
                          isEnabled: !project.slides.isEmpty) {
                showExport = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Mutations

    private func addImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        for image in images {
            guard let file = ImageStore.save(image) else { continue }
            let px = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
            project.slides.append(Slide(imageFile: file,
                                        sourcePixelWidth: px.width,
                                        sourcePixelHeight: px.height))
        }
        currentSlide = max(0, project.slides.count - 1)
        Haptics.success()
    }

    private func delete(_ slide: Slide) {
        ImageStore.delete(slide.imageFile)
        project.slides.removeAll { $0.id == slide.id }
        currentSlide = min(currentSlide, max(0, project.slides.count - 1))
        Haptics.warning()
    }

    private func move(from: Int, to: Int) {
        guard project.slides.indices.contains(from), to >= 0, to < project.slides.count else { return }
        let slide = project.slides.remove(at: from)
        project.slides.insert(slide, at: to)
        currentSlide = to
        Haptics.selection()
    }
}
