import SwiftUI

/// The editor. A live, pixel-accurate preview sits above a tabbed panel of
/// styling controls; the toolbar drives renaming and export. Every edit
/// autosaves through the `ProjectStore`, so the user never thinks about
/// "saving" — it just persists.
struct StudioView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var purchases: Store
    @Environment(\.dismiss) private var dismiss

    @State private var project: ScreenshotProject
    /// Selection is tracked by slide identity, not index, so adding, deleting
    /// or reordering slides can never desync the preview, filmstrip and panels.
    @State private var selectedSlideID: UUID?
    @State private var panel: Panel = .layout
    @State private var showPhotoPicker = false
    @State private var showExport = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var showImportOptions = false
    @State private var showVideoPicker = false
    @State private var frameBatch: FrameBatch?
    @State private var isExtractingVideo = false
    @State private var shareItem: ShareURLItem?
    @State private var paywallFeature: ProFeature?
    @State private var shareError: String?
    /// The project as it was opened, so closing without edits doesn't bump the
    /// modified date and silently reshuffle the gallery.
    @State private var original: ScreenshotProject

    init(project: ScreenshotProject) {
        _project = State(initialValue: project)
        _original = State(initialValue: project)
        _selectedSlideID = State(initialValue: project.slides.first?.id)
    }

    enum Panel: String, CaseIterable, Identifiable {
        case templates = "Templates", layout = "Layout", background = "Backdrop",
             caption = "Caption", overlays = "Overlays", enhance = "Enhance", device = "Sizes"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .templates: return "square.stack.3d.up.fill"
            case .layout: return "square.resize"
            case .background: return "paintbrush.fill"
            case .caption: return "textformat"
            case .overlays: return "plus.bubble.fill"
            case .enhance: return "wand.and.stars"
            case .device: return "iphone.gen3"
            }
        }
    }

    /// Index of the selected slide, resolved from identity at read time.
    private var selectedIndex: Int? {
        guard let id = selectedSlideID else { return nil }
        return project.slides.firstIndex { $0.id == id }
    }

    private var selectedSlide: Slide? {
        if let index = selectedIndex { return project.slides[index] }
        return project.slides.first
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
                .accessibilityLabel("Project name, \(project.name). Double tap to rename.")
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
        .confirmationDialog("Add to set", isPresented: $showImportOptions, titleVisibility: .visible) {
            Button("Photos") { showPhotoPicker = true }
            Button("App Preview video") {
                if purchases.isPro { showVideoPicker = true } else { paywallFeature = .videoFrames }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Import screenshots, or pull frames from an App Preview video.")
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { images in addImages(images) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker { url in
                guard let url else { return }
                withAnimation(.easeInOut) { isExtractingVideo = true }
                Task { @MainActor in
                    let frames = await VideoFrameExtractor.frames(from: url)
                    withAnimation(.easeInOut) { isExtractingVideo = false }
                    frameBatch = FrameBatch(images: frames)
                    try? FileManager.default.removeItem(at: url)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $frameBatch) { batch in
            FrameChooserSheet(frames: batch.images) { picked in addImages(picked) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(highlight: feature)
        }
        .overlay {
            if isExtractingVideo { extractingOverlay }
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
        .alert("Share failed", isPresented: Binding(
                    get: { shareError != nil },
                    set: { if !$0 { shareError = nil } }
                )) {
            Button("OK") { shareError = nil }
        } message: {
            Text(shareError ?? "An unknown error occurred.")
        }
        // Persist edits, but debounce disk writes so dragging a slider doesn't
        // hammer the file system every frame. A final save fires on close.
        .onChange(of: project) { _, newValue in scheduleSave(newValue) }
        .onChange(of: project.slides.count) { _, _ in
            // Keep selection valid if slides changed out from under us.
            if selectedSlideID == nil || !project.slides.contains(where: { $0.id == selectedSlideID }) {
                selectedSlideID = project.slides.first?.id
            }
        }
        .onDisappear {
            saveTask?.cancel()
            // Only persist when something actually changed, so simply opening
            // and closing a set doesn't bump its date and reshuffle the gallery.
            if project != original { store.upsert(project) }
        }
    }

    private var extractingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Reading video frames…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .transition(.opacity)
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
                TabView(selection: $selectedSlideID) {
                    ForEach(project.slides) { slide in
                        CanvasPreview(project: project, slide: slide)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 10)
                            .tag(Optional(slide.id))
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
                    let isSelected = slide.id == selectedSlideID
                    Button {
                        Motion.run(Motion.snap) { selectedSlideID = slide.id }
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
                        Button { duplicate(slide) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button { shareSlide(slide) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { delete(slide) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .accessibilityLabel("Screenshot \(index + 1) of \(project.slides.count)")
                    .draggable(slide.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        reorder(droppedID: items.first, onto: slide)
                    }
                }

                Button {
                    Haptics.tap()
                    showImportOptions = true
                } label: {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LiquidGlass.surface)
                        .frame(width: 46, height: 84)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(LiquidGlass.accent)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(LiquidGlass.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        ScrollView(.horizontal, showsIndicators: false) {
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
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? .white : LiquidGlass.primaryText.opacity(0.55))
                        .frame(width: 66)
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
        }
        .background(LiquidGlass.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .templates:  TemplatePanel(project: $project)
        case .layout:     LayoutPanel(project: $project)
        case .background: BackgroundPanel(project: $project)
        case .caption:    CaptionPanel(project: $project, slideIndex: selectedIndex)
        case .overlays:   OverlayPanel(project: $project)
        case .enhance:    EnhancePanel(project: $project)
        case .device:     DevicePanel(project: $project)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            PrimaryButton(title: "Add", systemImage: "photo.badge.plus", style: .glass) {
                showImportOptions = true
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
        // Free tier caps total screenshots per set; add what fits, then upsell.
        let capacity = purchases.isPro ? images.count
                                       : max(0, FreeTier.maxScreenshots - project.slides.count)
        let toAdd = Array(images.prefix(capacity))
        guard !toAdd.isEmpty else {
            paywallFeature = .moreScreenshots
            return
        }
        var lastAddedID: UUID?
        Motion.run(Motion.snap) {
            for image in toAdd {
                guard let file = ImageStore.save(image) else { continue }
                let px = CGSize(width: image.size.width * image.scale,
                                height: image.size.height * image.scale)
                let slide = Slide(imageFile: file,
                                  sourcePixelWidth: px.width,
                                  sourcePixelHeight: px.height)
                project.slides.append(slide)
                lastAddedID = slide.id
            }
            if let lastAddedID { selectedSlideID = lastAddedID }
        }
        Haptics.success()
        if !purchases.isPro && images.count > toAdd.count {
            paywallFeature = .moreScreenshots
        }
    }

    private func delete(_ slide: Slide) {
        guard let index = project.slides.firstIndex(where: { $0.id == slide.id }) else { return }
        ImageStore.delete(slide.imageFile)
        Motion.run(Motion.snap) {
            project.slides.remove(at: index)
            // Select a sensible neighbour so the editor never lands on nothing.
            if project.slides.isEmpty {
                selectedSlideID = nil
            } else if slide.id == selectedSlideID {
                selectedSlideID = project.slides[min(index, project.slides.count - 1)].id
            }
        }
        Haptics.warning()
    }

    /// Move a dragged slide so it lands at the dropped-on slide's position.
    @discardableResult
    private func reorder(droppedID raw: String?, onto target: Slide) -> Bool {
        guard let raw, let draggedID = UUID(uuidString: raw),
              let from = project.slides.firstIndex(where: { $0.id == draggedID }),
              let to = project.slides.firstIndex(where: { $0.id == target.id }),
              from != to else { return false }
        Motion.run(Motion.snap) {
            let moved = project.slides.remove(at: from)
            project.slides.insert(moved, at: to)
            selectedSlideID = moved.id
        }
        Haptics.selection()
        return true
    }

    /// Render one slide at the primary device resolution and hand it to the
    /// share sheet as a PNG file — a quick way to send a single screenshot.
    private func shareSlide(_ slide: Slide) {
        let canvasSize = project.deviceSize.pixelSize(for: project.orientation)
        guard let image = ScreenshotRenderer.render(
            canvasSize: canvasSize,
            style: project.style,
            image: ImageStore.load(slide.imageFile),
            captionText: project.captionText(for: slide),
            statusBarLayout: project.deviceSize.statusBarLayout
        ), let data = image.pngData() else {
            BugLog.warning("Share", "Couldn't render the slide for sharing.")
            shareError = "Couldn't render the slide for sharing."
            Haptics.error()
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotStudio-\(UUID().uuidString).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else {
            shareError = "Couldn't save the image for sharing."
            Haptics.error()
            return
        }
        shareItem = ShareURLItem(url: url)
        Haptics.tap()
    }

    private func duplicate(_ slide: Slide) {
        guard let index = project.slides.firstIndex(where: { $0.id == slide.id }),
              let file = ImageStore.copy(slide.imageFile) else { return }
        var copy = slide
        copy.id = UUID()
        copy.imageFile = file
        Motion.run(Motion.snap) {
            project.slides.insert(copy, at: index + 1)
            selectedSlideID = copy.id
        }
        Haptics.success()
    }

    private func move(from: Int, to: Int) {
        guard project.slides.indices.contains(from), to >= 0, to < project.slides.count else { return }
        Motion.run(Motion.snap) {
            let slide = project.slides.remove(at: from)
            project.slides.insert(slide, at: to)
            selectedSlideID = slide.id
        }
        Haptics.selection()
    }
}

/// Identifiable wrapper so a single shared file URL can drive `.sheet(item:)`.
private struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
}
