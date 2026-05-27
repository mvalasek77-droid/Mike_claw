import SwiftUI
import PhotosUI

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

    enum Phase { case form, reviewing, verdict }

    private let stepTitles = ["Format", "Details", "AI Disclosure", "Content", "Cover Art", "Pricing", "Review"]
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
                    if let id = submissionID {
                        let verdict = store.runReview(for: id)
                        result = verdict
                        if let verdict, store.aiAutopilotEnabled, verdict.aiChoosesToPublish {
                            store.publish(submissionID: id)
                            autoPublished = true
                        }
                    }
                    Motion.run(.easeInOut(duration: 0.4)) { phase = .verdict }
                }
            case .verdict:
                if let result, let id = submissionID {
                    ReviewVerdictView(draft: draft, result: result, submissionID: id,
                                      autoPublished: autoPublished,
                                      onReviseAgain: { phase = .form; step = 1 },
                                      onClose: { dismiss() })
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
        case 5: PricingStep(draft: $draft)
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

    /// Per-step validation gating the Continue button.
    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return !draft.title.trimmed.isEmpty && !draft.creator.trimmed.isEmpty
            && !draft.genre.trimmed.isEmpty && draft.synopsis.trimmed.count >= 20
        case 2: return !draft.aiTools.isEmpty
        case 3: return draft.fileName != nil
        case 4: return draft.coverImageData != nil
        case 5: return draft.price >= 0.99
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
            }

            LengthStepper(draft: $draft)
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

// MARK: - Step 3: Content upload

private struct ContentStep: View {
    @Binding var draft: DraftWork

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload your \(draft.contentVerbed). We accept the final, production-ready file.")
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
                        Button { draft.fileName = nil } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.warning)
                        }
                    }
                }
            } else {
                Button { attach() } label: {
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
            }
        }
    }

    private var acceptedTypes: String {
        switch draft.type {
        case .novel: return "EPUB, DOCX or PDF"
        case .music: return "WAV or FLAC master"
        case .movie: return "MP4 or MOV, up to 4K"
        }
    }

    private func attach() {
        let ext: String
        switch draft.type {
        case .novel: ext = "epub"
        case .music: ext = "wav"
        case .movie: ext = "mp4"
        }
        let base = draft.title.trimmed.isEmpty ? "untitled" : draft.title.trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
        draft.fileName = "\(base).\(ext)"
        draft.fileSizeMB = Double((stableHash(base) % 900) + 40) / (draft.type == .movie ? 1 : 10)
        Haptics.success()
    }
}

// MARK: - Step 4: Cover art

private struct CoverStep: View {
    @Binding var draft: DraftWork
    @State private var selection: PhotosPickerItem?

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
                        draft.coverImageData = data
                        Haptics.success()
                    }
                }
            }
        }
    }
}

// MARK: - Step 5: Pricing

private struct PricingStep: View {
    @Binding var draft: DraftWork

    private var fee: Double { Commerce.platformFee(on: draft.price) }
    private var earning: Double { Commerce.creatorEarning(on: draft.price) }

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

            GlassCard(title: "How you get paid", icon: "percent", tint: Theme.kdp) {
                VStack(spacing: 10) {
                    payoutRow("List price", draft.price, color: Theme.ink)
                    payoutRow("Apple App Store cut", nil, color: Theme.inkSoft)
                    payoutRow("AI Marketplace fee (15%)", -fee, color: Theme.warning)
                    Divider().overlay(Theme.hairline)
                    payoutRow("You earn per sale (85%)", earning, color: Theme.success, bold: true)
                    Text(Commerce.appleFeeNote)
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

    private func payoutRow(_ label: String, _ amount: Double?, color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: bold ? .bold : .medium, design: .rounded)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(amount == nil ? "15–30%" : String(format: "%@$%.2f", amount! < 0 ? "−" : "", abs(amount!)))
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

// MARK: - Step 6: Review

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
                    summaryRow("You earn", String(format: "$%.2f per sale (85%%)", Commerce.creatorEarning(on: draft.price)))
                    Text(Commerce.appleFeeNote)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
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
