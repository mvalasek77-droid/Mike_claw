import SwiftUI
import PhotosUI

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

    private var isNew: Bool { original == nil }

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
    }

    private func load() {
        guard let o = original else { return }
        title = o.title; creator = o.creator; type = o.type; genre = o.genre
        synopsis = o.synopsis; price = o.price; score = Double(o.commercialScore)
        aiTools = o.aiTools.joined(separator: ", "); coverData = o.coverImageData
    }

    private func save() {
        let tools = aiTools.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        let item = MediaItem(
            id: original?.id ?? UUID(),
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
            isEditorOriginal: original?.isEditorOriginal ?? false
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
