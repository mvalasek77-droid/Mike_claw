import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Add or adjust a title with full admin control over every field.
struct AdminEditView: View {
    /// nil = creating a new title.
    let original: MediaItem?
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var creator = ""
    @State private var type: MediaType = .novel
    @State private var genre = ""
    @State private var synopsis = ""
    @State private var price: Double = 4.99
    @State private var score: Double = 90
    @State private var aiTools = ""
    @State private var coverData: Data?
    @State private var coverPick: PhotosPickerItem?

    // Content upload. Novels carry their full text in `manuscript`; music
    // and film carry a picked file the store copies into Documents/published
    // at save time. `mediaURL` is the security-scoped pick; `mediaPickedName`
    // is just for display. An existing title's already-saved file shows as
    // "current file on record" until replaced.
    @State private var manuscript = ""
    @State private var mediaURL: URL?
    @State private var mediaPickedName: String?
    @State private var showFileImporter = false

    private var isNew: Bool { original == nil }

    /// Content types the file importer accepts for the current media type.
    private var allowedContentTypes: [UTType] {
        switch type {
        case .music: return [.audio, .mp3, .mpeg4Audio, .wav]
        case .movie: return [.movie, .mpeg4Movie, .quickTimeMovie, .video]
        case .novel: return [.plainText, .text, .utf8PlainText]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    coverPicker
                    field("Title", $title, "Title")
                    field("Creator", $creator, "Creator / artist")
                    typePicker
                    field("Genre", $genre, "e.g. Sci-Fi")
                    field("AI tools", $aiTools, "comma-separated, e.g. Suno, GPT-4")
                    editor("Synopsis", $synopsis)
                    contentSection
                    slider("Price", value: $price, range: 0.99...19.99, step: 0.5, format: "$%.2f")
                    slider("Commercial score", value: $score, range: 50...100, step: 1, format: "%.0f%%")

                    PrimaryButton(title: isNew ? "Add title" : "Save changes", systemImage: "checkmark",
                                  tint: Theme.success, enabled: !title.trimmed.isEmpty) { save() }
                    if !isNew {
                        PrimaryButton(title: "Delete title", systemImage: "trash", style: .ghost, tint: Theme.warning) {
                            if let id = original?.id { store.adminDelete(id) }
                            dismiss()
                        }
                    }
                }
                .padding(18).padding(.bottom, 30)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(isNew ? "Add title" : "Edit title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear(perform: load)
        .onChange(of: coverPick) { _, new in
            guard let new else { return }
            Task { if let d = try? await new.loadTransferable(type: Data.self) { await MainActor.run { coverData = d } } }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let picked = urls.first else { return }
            if type == .novel {
                // For novels we read the text in-line so the manuscript is
                // carried on the item directly (the picker URL dies after).
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: picked, encoding: .utf8) {
                    manuscript = text
                }
            } else {
                // For music/film the store copies the file at save time.
                mediaURL = picked
                mediaPickedName = picked.lastPathComponent
            }
            Haptics.tap()
        }
    }

    /// Content upload, type-aware. Novels get a manuscript editor + a
    /// "Load .txt" importer; music/film get a file picker for the playable
    /// asset. Without this an admin-added title had cover art + metadata but
    /// nothing for the buyer to actually read / play.
    @ViewBuilder
    private var contentSection: some View {
        switch type {
        case .novel:
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Manuscript").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Button {
                        showFileImporter = true   // allowedContentTypes already filters to text
                    } label: {
                        Label("Load .txt", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    }.buttonStyle(.plain)
                }
                TextEditor(text: $manuscript).frame(minHeight: 160).padding(6).scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                    .foregroundStyle(Theme.ink).font(.system(size: 14))
                Text(manuscript.isEmpty
                     ? "Paste the full text or load a .txt file. This is what the buyer reads."
                     : "\(manuscriptWordCount) words")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
        case .music, .movie:
            VStack(alignment: .leading, spacing: 5) {
                Text(type == .music ? "Audio file" : "Video file")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Button { showFileImporter = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: type == .music ? "music.note" : "film")
                            .foregroundStyle(Theme.accent)
                        Text(mediaPickedName
                             ?? (original?.localMediaFileName != nil ? "Current file on record · tap to replace" : "Choose a file to upload"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(mediaPickedName != nil || original?.localMediaFileName != nil ? Theme.ink : Theme.inkSoft)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                }.buttonStyle(.plain)
                Text(type == .music
                     ? "MP3 / M4A / WAV — what plays when a buyer opens the title."
                     : "MP4 / MOV — what plays when a buyer opens the title.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var manuscriptWordCount: Int {
        manuscript.split(whereSeparator: { $0 == " " || $0.isNewline }).count
    }

    private func load() {
        guard let o = original else { return }
        title = o.title; creator = o.creator; type = o.type; genre = o.genre
        synopsis = o.synopsis; price = o.price; score = Double(o.commercialScore)
        aiTools = o.aiTools.joined(separator: ", "); coverData = o.coverImageData
        manuscript = o.manuscriptText ?? ""
    }

    private func save() {
        let tools = aiTools.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        let itemID = original?.id ?? UUID()

        // Carry content through to the item so the buyer can actually
        // read/play it. Novels store the manuscript text directly; music
        // and film copy the newly-picked file into permanent storage (if
        // none was picked this edit, keep whatever was already on record).
        let manuscriptText: String? = (type == .novel)
            ? (manuscript.trimmed.isEmpty ? nil : manuscript)
            : nil
        let localMediaFileName: String?
        if type != .novel, let url = mediaURL {
            localMediaFileName = store.adminImportMedia(from: url, itemID: itemID)
        } else {
            localMediaFileName = original?.localMediaFileName
        }

        let item = MediaItem(
            id: itemID,
            title: title.trimmed,
            creator: creator.trimmed.isEmpty ? "AI Marketplace" : creator.trimmed,
            type: type,
            genre: genre.trimmed.isEmpty ? "General" : genre.trimmed,
            synopsis: synopsis.trimmed,
            aiTools: tools.isEmpty ? ["AI"] : tools,
            commercialScore: Int(score),
            price: price,
            length: original?.length ?? (type == .music ? 1 : type == .novel ? 200 : 100),
            maturity: original?.maturity ?? "13+",
            purchases: original?.purchases ?? 0,
            trending: original?.trending ?? 60,
            addedAt: original?.addedAt ?? .now,
            coverImageData: coverData,
            coverAssetName: original?.coverAssetName,
            mediaFileName: original?.mediaFileName,
            isEditorOriginal: original?.isEditorOriginal ?? false,
            localMediaFileName: localMediaFileName,
            manuscriptText: manuscriptText
        )
        if isNew { store.adminAdd(item) } else { store.adminUpdate(item) }
        dismiss()
    }

    private var coverPicker: some View {
        PhotosPicker(selection: $coverPick, matching: .images) {
            ZStack {
                if let coverData, let img = UIImage(data: coverData) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 160).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerM))
                } else {
                    RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)).frame(height: 120)
                        .overlay(Label("Cover art (optional)", systemImage: "photo").foregroundStyle(Theme.inkSoft))
                }
            }
        }.buttonStyle(.plain)
    }

    private var typePicker: some View {
        HStack(spacing: 8) {
            ForEach(MediaType.allCases) { t in
                Button { type = t } label: {
                    Text(t.title).font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(type == t ? .black : Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(type == t ? t.accent : .white.opacity(0.06)))
                }.buttonStyle(.plain)
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            TextField(placeholder, text: text).foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
        }
    }

    private func editor(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            TextEditor(text: text).frame(minHeight: 90).padding(6).scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                .foregroundStyle(Theme.ink).font(.system(size: 14))
        }
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(String(format: format, value.wrappedValue)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            }
            Slider(value: value, in: range, step: step).tint(Theme.accent)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: format, value.wrappedValue))
        }
    }
}
