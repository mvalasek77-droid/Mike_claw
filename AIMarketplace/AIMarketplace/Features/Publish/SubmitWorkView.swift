import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The KDP-style title registration wizard. Walks the creator through type,
/// details, AI disclosure, content upload and pricing, then hands the draft to
/// the AI Editor for review.
struct SubmitWorkView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DraftWork()
    @State private var step = 0
    @State private var phase: Phase = .form
    @State private var submissionID: UUID?
    @State private var result: AIReviewResult?
    @State private var autoPublished = false
    /// Non-nil when the editor couldn't produce a verdict (network race,
    /// submission lookup miss, etc). Drives the .verdict error-card path so
    /// the screen is never blank — that blank state was the "loops back to
    /// the beginning" bug.
    @State private var reviewError: String?

    enum Phase { case form, reviewing, verdict }

    private let stepTitles = ["Format", "Details", "AI Disclosure", "Content", "Cover Art", "Attestation", "Pricing", "Review"]
    private var lastStep: Int { stepTitles.count - 1 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.04), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch phase {
            case .form: formFlow
            case .reviewing:
                AIReviewProgressView(draft: draft) {
                    Task { @MainActor in
                        guard let id = submissionID else {
                            reviewError = "We lost the submission while preparing the review. Tap Try again."
                            Motion.run(.easeInOut(duration: 0.4)) { phase = .verdict }
                            return
                        }
                        let verdict = await store.runReviewAsync(for: id)
                        if let verdict {
                            result = verdict
                            reviewError = nil
                            if store.aiAutopilotEnabled, verdict.aiChoosesToPublish {
                                store.publish(submissionID: id)
                                autoPublished = true
                            }
                        } else {
                            // The Editor couldn't produce a verdict in time —
                            // file unreadable, security-scoped URL lapsed, or
                            // the analysis hit the 60 s timeout. Never blank
                            // the screen; show a recoverable error.
                            reviewError = "The review timed out reading your file. Re-pick it (the iOS access permission may have expired), then Try again."
                        }
                        Motion.run(.easeInOut(duration: 0.4)) { phase = .verdict }
                    }
                }
            case .verdict:
                if let result, let id = submissionID {
                    ReviewVerdictView(draft: draft, result: result, submissionID: id,
                                      autoPublished: autoPublished,
                                      onReviseAgain: { phase = .form; step = 1 },
                                      onClose: { dismiss() })
                } else {
                    // ALWAYS render something for .verdict — the empty-view
                    // case was the bug. Recoverable error card with a single
                    // "Try again" button that re-runs the review.
                    reviewErrorCard
                }
            }
        }
    }

    // MARK: - Form flow

    private var formFlow: some View {
        VStack(spacing: 0) {
            topBar
            ProgressDots(count: stepTitles.count, current: step, tint: Theme.kdp)
                .padding(.vertical, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(stepTitles[step])
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    stepContent
                }
                .screenPadding()
                .padding(.top, 4)
                .padding(.bottom, 30)
            }

            footer
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Text("Register Title")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(step + 1)/\(stepTitles.count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: FormatStep(draft: $draft)
        case 1: DetailsStep(draft: $draft)
        case 2: DisclosureStep(draft: $draft)
        case 3: ContentStep(draft: $draft)
        case 4: CoverStep(draft: $draft)
        case 5: AttestationStep(draft: $draft)
        case 6: PricingStep(draft: $draft)
        default: ReviewStep(draft: draft)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                PrimaryButton(title: "Back", style: .ghost) {
                    Motion.run(Motion.snap) { step -= 1 }
                }
                .frame(width: 110)
            }
            if step < lastStep {
                PrimaryButton(title: "Continue", systemImage: "arrow.right",
                              tint: Theme.kdp, enabled: canAdvance) {
                    Motion.run(Motion.snap) { step += 1 }
                }
            } else {
                PrimaryButton(title: "Submit to AI Editor", systemImage: "sparkles",
                              tint: Theme.kdp, enabled: draft.canSubmit) {
                    submissionID = store.createSubmission(draft)
                    Motion.run(.easeInOut(duration: 0.4)) { phase = .reviewing }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    /// Shown when phase == .verdict but no review result is available. This
    /// is the safety net for the "won't go to the editor" bug — the screen
    /// is never blank, and the user can always retry without restarting.
    private var reviewErrorCard: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56)).foregroundStyle(Theme.warning)
            Text("Review didn't complete")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(reviewError ?? "The AI Editor didn't return a verdict. Try again — your draft is still here.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            PrimaryButton(title: "Try again", systemImage: "arrow.clockwise",
                          tint: Theme.kdp) {
                reviewError = nil
                if submissionID == nil { submissionID = store.createSubmission(draft) }
                Motion.run(.easeInOut(duration: 0.4)) { phase = .reviewing }
            }
            PrimaryButton(title: "Back to draft", style: .ghost) {
                phase = .form
            }
            Spacer()
        }
        .screenPadding()
    }

    /// Per-step validation gating the Continue button.
    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return !draft.title.trimmed.isEmpty && !draft.creator.trimmed.isEmpty
            && !draft.genre.trimmed.isEmpty && draft.synopsis.trimmed.count >= 20
        case 2: return !draft.aiTools.isEmpty
        case 3: return draft.fileName != nil && (draft.contentURL != nil || draft.manuscriptText != nil)
        case 4: return CoverStep.isHighQuality(draft.coverImageData)
        case 5: return draft.hasAttested
        case 6: return draft.price >= 0.99
        default: return true
        }
    }
}

// MARK: - Progress dots

struct ProgressDots: View {
    let count: Int
    let current: Int
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? tint : Color.white.opacity(0.15))
                    .frame(width: i == current ? 22 : 8, height: 6)
            }
        }
        .animation(.spring(response: 0.3), value: current)
    }
}

// MARK: - Step 0: Format

private struct FormatStep: View {
    @Binding var draft: DraftWork

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you publishing?")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            ForEach(MediaType.allCases) { type in
                Button {
                    Haptics.selection()
                    Motion.run(Motion.snap) {
                        draft.type = type
                        draft.length = defaultLength(type)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: type.icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(type.accent)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(type.accent.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.plural)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text(blurb(type))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Image(systemName: draft.type == type ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(draft.type == type ? type.accent : Theme.inkFaint)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerM)
                            .fill(draft.type == type ? type.accent.opacity(0.12) : .white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerM)
                            .strokeBorder(draft.type == type ? type.accent.opacity(0.6) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func blurb(_ type: MediaType) -> String {
        switch type {
        case .novel: return "Full-length fiction or non-fiction"
        case .music: return "Albums, EPs and singles"
        case .movie: return "Features, shorts and series"
        }
    }

    private func defaultLength(_ type: MediaType) -> Int {
        switch type {
        case .novel: return 280
        case .music: return 9
        case .movie: return 95
        }
    }
}

// MARK: - Step 1: Details

private struct DetailsStep: View {
    @Binding var draft: DraftWork
    @State private var aiDrafting = false

    private var genres: [String] {
        switch draft.type {
        case .novel: return ["Literary Fiction", "Thriller", "Romance", "Fantasy", "Sci-Fi", "Horror", "Mystery", "Young Adult"]
        case .music: return ["Pop", "Electronic", "Synthwave", "Ambient", "Hip-Hop", "Indie Folk", "Classical", "Lo-fi"]
        case .movie: return ["Drama", "Sci-Fi", "Thriller", "Comedy", "Horror", "Documentary", "Action", "Animation"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Title", text: $draft.title, placeholder: "Your \(draft.type.title.lowercased()) title", icon: "textformat")
            LabeledField(label: "Subtitle (optional)", text: $draft.subtitle, placeholder: "A short tagline", icon: "text.alignleft")
            LabeledField(label: "Creator / pen name", text: $draft.creator, placeholder: "Who gets the credit", icon: "person")

            VStack(alignment: .leading, spacing: 6) {
                Text("Genre").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                FlexibleHStack(spacing: 8, lineSpacing: 8) {
                    ForEach(genres, id: \.self) { g in
                        Button { Haptics.selection(); draft.genre = g } label: {
                            Chip(text: g, color: draft.type.accent, filled: draft.genre == g)
                        }.buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Synopsis").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("\(draft.synopsis.trimmed.count) chars · min 20")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(draft.synopsis.trimmed.count >= 20 ? Theme.success : Theme.inkFaint)
                }
                TextEditor(text: $draft.synopsis)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 130)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerS).strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
                onDeviceAIRow
            }

            LengthStepper(draft: $draft)
        }
    }

    @ViewBuilder private var onDeviceAIRow: some View {
        switch OnDeviceAI.status {
        case .ready:
            Button {
                aiDrafting = true
                Task {
                    if let text = await OnDeviceAI.draftSynopsis(type: draft.type, title: draft.title,
                                                                 genre: draft.genre, existing: draft.synopsis) {
                        draft.synopsis = text
                        Haptics.success()
                    }
                    aiDrafting = false
                }
            } label: {
                HStack(spacing: 6) {
                    if aiDrafting { ProgressView().controlSize(.small) }
                    else { Image(systemName: "sparkles") }
                    Text(aiDrafting ? "Drafting on device…" : "Draft with on-device AI")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
            }
            .disabled(aiDrafting)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
        case .unsupported:
            EmptyView()   // older OS/toolchain: hide the option entirely
        }
    }
}

private struct LengthStepper: View {
    @Binding var draft: DraftWork

    private var unit: String {
        switch draft.type {
        case .novel: return "pages"
        case .music: return "tracks"
        case .movie: return "minutes"
        }
    }
    private var step: Int { draft.type == .music ? 1 : (draft.type == .novel ? 10 : 5) }

    var body: some View {
        HStack {
            Text("Length")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            HStack(spacing: 14) {
                stepButton("minus") { draft.length = max(1, draft.length - step) }
                Text("\(draft.length) \(unit)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 100)
                stepButton("plus") { draft.length += step }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Step 2: AI Disclosure

private struct DisclosureStep: View {
    @Binding var draft: DraftWork

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which AI systems produced this work? Disclosure is required for every title on the marketplace.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)

            FlexibleHStack(spacing: 8, lineSpacing: 8) {
                ForEach(AIToolCatalog.suggestions(for: draft.type), id: \.self) { tool in
                    Button {
                        Haptics.selection()
                        toggle(tool)
                    } label: {
                        Chip(text: tool, systemImage: draft.aiTools.contains(tool) ? "checkmark" : "sparkles",
                             color: draft.type.accent, filled: draft.aiTools.contains(tool))
                    }.buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("Add another tool…", text: $draft.customTool)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                Button {
                    let t = draft.customTool.trimmed
                    guard !t.isEmpty, !draft.aiTools.contains(t) else { return }
                    draft.aiTools.append(t); draft.customTool = ""; Haptics.success()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(Theme.kdp))
                }.buttonStyle(.plain)
            }

            if !draft.aiTools.isEmpty {
                GlassCard(title: "Declared", icon: "checkmark.seal.fill", tint: Theme.success) {
                    FlexibleHStack(spacing: 8, lineSpacing: 8) {
                        ForEach(draft.aiTools, id: \.self) { tool in
                            Button { draft.aiTools.removeAll { $0 == tool } } label: {
                                Chip(text: tool, systemImage: "xmark", color: Theme.success, filled: true)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ tool: String) {
        if draft.aiTools.contains(tool) { draft.aiTools.removeAll { $0 == tool } }
        else { draft.aiTools.append(tool) }
    }
}

// MARK: - Step 3: Content upload (REAL FILE CAPTURE)

private struct ContentStep: View {
    @Binding var draft: DraftWork
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload your \(draft.contentVerbed). We accept the final, production-ready file. The AI Editor opens and reads the actual bytes — placeholder names won't pass.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)

            if let name = draft.fileName {
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill.badge.plus")
                            .font(.system(size: 24)).foregroundStyle(Theme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(String(format: "%.1f MB · uploaded", draft.fileSizeMB))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Button {
                            // Clear ALL real-content fields, not just the display name.
                            draft.fileName = nil
                            draft.fileSizeMB = 0
                            draft.contentURL = nil
                            draft.manuscriptText = nil
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.warning)
                        }
                    }
                }
            } else {
                Button { importing = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.up.doc.fill")
                            .font(.system(size: 40)).foregroundStyle(Theme.kdp)
                        Text("Tap to upload \(draft.contentVerbed)")
                            .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        Text(acceptedTypes)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerL)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundStyle(Theme.kdp.opacity(0.5))
                    )
                }.buttonStyle(.plain)
                .fileImporter(isPresented: $importing,
                              allowedContentTypes: contentTypes,
                              allowsMultipleSelection: false) { result in
                    handleImport(result)
                }
            }

            if let err = importError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private var acceptedTypes: String {
        switch draft.type {
        case .novel: return "Plain text, RTF or PDF manuscript"
        case .music: return "WAV, AIFF or MP3 master"
        case .movie: return "MP4 or MOV film file"
        }
    }

    /// UTType filters by media kind — the `.fileImporter` won't even show
    /// inappropriate files. This is the iOS analogue of an `accept=` filter.
    /// We deliberately keep the type lists narrow but correct: only types we
    /// can actually decode downstream make it in. The abstract supertypes
    /// (`.audio`, `.movie`) cover their concrete variants (WAV/AIFF/MP3/etc).
    private var contentTypes: [UTType] {
        switch draft.type {
        case .novel:
            return [.plainText, .rtf, .pdf, .text]
        case .music:
            return [.audio, .mp3, .wav, .mpeg4Audio]
        case .movie:
            return [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            captureFile(at: url)
        case .failure(let error):
            importError = "Couldn't import file: \(error.localizedDescription)"
        }
    }

    private func captureFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        // We INTENTIONALLY hold the URL only; the URL retains scoped access via
        // its security-scoped wrapper until we relinquish it on submit. For
        // novels we also slurp the bytes into memory so re-analysis works even
        // after the picker's scope ends (manuscripts are small).
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeMB = Double(size) / 1_048_576
        let name = url.lastPathComponent

        // Validate by actually opening the file. If it fails to decode, surface
        // an error rather than carrying a broken upload to scoring.
        switch draft.type {
        case .novel:
            if let text = ContentAnalysis.readTextFromFile(at: url) {
                draft.manuscriptText = text
                draft.contentURL = url
                draft.fileName = name
                draft.fileSizeMB = sizeMB
                Haptics.success()
            } else {
                importError = "Couldn't read text from this file. Please choose a .txt, .rtf or .pdf manuscript."
            }
        case .music:
            // We don't decode the whole file here — just verify it opens.
            let testReport = ContentAnalysis.analyseAudio(at: url)
            if testReport.decodedSuccessfully {
                draft.contentURL = url
                draft.fileName = name
                draft.fileSizeMB = sizeMB
                Haptics.success()
            } else {
                importError = "Couldn't decode this audio file. The Editor needs a WAV / AIFF / MP3 master."
            }
        case .movie:
            // Async probe; we trust the picker's UTType filter and verify on review.
            draft.contentURL = url
            draft.fileName = name
            draft.fileSizeMB = sizeMB
            Haptics.success()
        }
    }
}

// MARK: - Step 4: Cover art

private struct CoverStep: View {
    @Binding var draft: DraftWork
    @State private var selection: PhotosPickerItem?
    @State private var lastRejectReason: String?

    /// A cover passes if it has real dimensions AND a real file size. A
    /// 1×1 JPEG or a 4-byte sentinel both fail; a creator can either pick a
    /// higher-quality image or tap "Let the app create one for me" — that
    /// last path renders a procedural cover so the slot is never blocked
    /// behind missing artwork.
    static let minSidePx: CGFloat = 600
    static let minBytes = 30 * 1024

    static func isHighQuality(_ data: Data?) -> Bool {
        guard let data, data.count >= minBytes,
              let image = UIImage(data: data) else { return false }
        return image.size.width >= minSidePx && image.size.height >= minSidePx
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add your \(draft.coverNoun). This is the artwork buyers see across the store, the Top 10 and their library. Square or portrait art looks best.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)

            PhotosPicker(selection: $selection, matching: .images) {
                if let data = draft.coverImageData, let image = UIImage(data: data) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous))
                        Chip(text: "Change", systemImage: "photo", color: .white, filled: true).padding(12)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 40)).foregroundStyle(Theme.kdp)
                        Text("Choose \(draft.coverNoun)")
                            .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("From your photo library")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerL)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                            .foregroundStyle(Theme.kdp.opacity(0.5))
                    )
                }
            }
            .buttonStyle(.plain)
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        if Self.isHighQuality(data) {
                            draft.coverImageData = data
                            lastRejectReason = nil
                            Haptics.success()
                        } else {
                            // High-quality OR denied — Apple-friendly minimum is
                            // ≥600px per side and a real-file-size JPEG/PNG.
                            let img = UIImage(data: data)
                            let w = Int(img?.size.width ?? 0)
                            let h = Int(img?.size.height ?? 0)
                            lastRejectReason = "That image is too small for the storefront. We need at least 600×600 — you picked \(w)×\(h). Choose a higher-resolution image, or let the app generate one for you."
                            draft.coverImageData = nil
                            Haptics.warning()
                        }
                    }
                }
            }
        }
        if let lastRejectReason {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                Text(lastRejectReason)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
        }
        Button {
            generateProceduralCover()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("Let the app generate one for me")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().stroke(Theme.accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        Text("Procedurally generated covers are always full resolution and pass the cover-quality check.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.inkFaint)
    }

    @MainActor
    private func generateProceduralCover() {
        // Render the same GeneratedCover the app uses elsewhere into a
        // 1024×1024 JPEG, so the resulting cover passes isHighQuality.
        let stub = MediaItem(
            title: draft.title.trimmed.isEmpty ? "Untitled" : draft.title.trimmed,
            creator: draft.creator.trimmed.isEmpty ? "Creator" : draft.creator.trimmed,
            type: draft.type,
            genre: draft.genre.trimmed.isEmpty ? draft.type.title : draft.genre.trimmed,
            synopsis: draft.synopsis.trimmed,
            aiTools: draft.aiTools,
            commercialScore: 90,
            price: draft.price,
            length: max(draft.length, 1),
            maturity: draft.maturity,
            purchases: 0,
            trending: 70
        )
        let renderer = ImageRenderer(content:
            GeneratedCover(item: stub)
                .frame(width: 1024, height: 1024)
        )
        renderer.scale = 2
        if let image = renderer.uiImage,
           let data = image.jpegData(compressionQuality: 0.92) {
            draft.coverImageData = data
            lastRejectReason = nil
            Haptics.success()
        }
    }
}

// MARK: - Step 5: Creator attestation

/// Structured affirmation that the creator owns the rights to what they're
/// publishing. This is not a magic copyright check — it's an explicit, recorded
/// claim. The AI Editor will downscore the "copyright_risk" signal when the
/// attestation is missing or contradicts what it sees in the content (e.g.
/// famous-IP names in the manuscript while the creator swears it's original).
private struct AttestationStep: View {
    @Binding var draft: DraftWork

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Creator attestation")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("All three boxes below must be ticked before the AI Editor will review your work. False claims may result in removal and the forfeiture of earnings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)

            attestRow(
                title: "I own this work",
                detail: "I created or hold the rights to this \(draft.contentVerbed). It is not a substantial copy of any existing copyrighted material.",
                bound: $draft.attestOwnsWork
            )
            attestRow(
                title: "I own the prompts and inputs",
                detail: "Any prompts, briefs, source images, samples, datasets or other inputs used to make this work are mine to use commercially.",
                bound: $draft.attestOwnsPrompts
            )
            attestRow(
                title: "No infringement",
                detail: "This work does not knowingly include trademarked characters, brands, lyrics, dialogue, melodies, footage or likenesses I am not licensed to use.",
                bound: $draft.attestNoInfringement
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Signature")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                TextField("Type your full legal name", text: $draft.attestSignature)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.kdp)
                Text("The Editor still runs automated checks — lorem-ipsum manuscripts, silent audio, broken video, famous-IP names and near-duplicate covers are caught regardless of what's claimed here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func attestRow(title: String, detail: String, bound: Binding<Bool>) -> some View {
        Button { bound.wrappedValue.toggle(); Haptics.selection() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: bound.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(bound.wrappedValue ? Theme.success : Theme.inkFaint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Step 6: Pricing

private struct PricingStep: View {
    @Binding var draft: DraftWork

    private var split: Commerce.Breakdown { Commerce.breakdown(for: draft.price) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("List price").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                HStack {
                    Text(String(format: "$%.2f", draft.price))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    HStack(spacing: 12) {
                        priceButton("minus") { draft.price = max(0.99, draft.price - 1) }
                        priceButton("plus") { draft.price = min(19.99, draft.price + 1) }
                    }
                }
                Slider(value: $draft.price, in: 0.99...19.99, step: 0.50)
                    .tint(Theme.kdp)
            }

            GlassCard(title: "Where each $\(String(format: "%.2f", draft.price)) goes", icon: "percent", tint: Theme.kdp) {
                VStack(spacing: 10) {
                    payoutRow("Buyer pays", split.gross, color: Theme.ink, bold: true)
                    payoutRow("Apple's commission (\(Commerce.appleCutLabel))", -split.appleCut, color: Theme.inkSoft)
                    Divider().overlay(Theme.hairline)
                    payoutRow("Net proceeds", split.net, color: Theme.ink)
                    payoutRow("You keep (85%)", split.creator, color: Theme.success, bold: true)
                    payoutRow("AI Marketplace (15%)", split.marketplace, color: Theme.inkSoft)
                    Divider().overlay(Theme.hairline)
                    Text("Apple takes its App Store commission on every sale; the 85/15 split applies to what's left.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.kdp)
                Text(Commerce.explainer)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.accent)
                Text(Commerce.dynamicPricingNote)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func payoutRow(_ label: String, _ amount: Double, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: bold ? .bold : .medium, design: .rounded)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(String(format: "%@$%.2f", amount < 0 ? "−" : "", abs(amount)))
                .font(.system(size: bold ? 17 : 14, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func priceButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Step 7: Review

private struct ReviewStep: View {
    let draft: DraftWork
    @EnvironmentObject private var store: MarketplaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm your submission. The AI Editor will score it against the 85% commercial bar.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)

            HStack(alignment: .top, spacing: 14) {
                if let data = draft.coverImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 84, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title.trimmed.isEmpty ? "Untitled" : draft.title.trimmed)
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("by \(draft.creator.trimmed.isEmpty ? "—" : draft.creator.trimmed)")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    Chip(text: draft.type.title, systemImage: draft.type.icon, color: draft.type.accent)
                }
                Spacer()
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("Genre", draft.genre.isEmpty ? "—" : draft.genre)
                    summaryRow("Length", "\(draft.length) \(draft.type == .novel ? "pages" : draft.type == .music ? "tracks" : "min")")
                    summaryRow("AI tools", draft.aiTools.joined(separator: ", "))
                    summaryRow("File", draft.fileName ?? "—")
                    summaryRow("Price", String(format: "$%.2f", draft.price))
                    summaryRow("You earn", String(format: "$%.2f per sale", Commerce.creatorEarning(on: draft.price)))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $store.aiAutopilotEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").foregroundStyle(Theme.kdp)
                            Text("AI Autopilot")
                                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        }
                    }
                    .tint(Theme.kdp)
                    Text("Let the AI Editor publish this for you the moment it clears the 85% bar — but only when it's confident in its own verdict. Borderline passes are held for your sign-off.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.kdp)
                Text("Works under 85% are returned with notes you can act on and resubmit.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 80, alignment: .leading)
            if let icon { Image(systemName: icon).foregroundStyle(Theme.inkSoft) }
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
