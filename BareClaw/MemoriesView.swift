import SwiftUI

// MARK: - MemoriesView
//
// Displays memories the companion has formed about you.
// Backed by HermesMemory — the same system the companion uses
// when building context for every conversation.

struct MemoriesView: View {

    @State private var entries:           [MemoryEntry] = []
    @State private var isLoading:         Bool = true
    @State private var editingEntry:      MemoryEntry? = nil
    @State private var deleteTarget:      UUID? = nil
    @State private var showDeleteConfirm  = false
    @State private var searchText:        String = ""

    private var filteredEntries: [MemoryEntry] {
        guard !searchText.isEmpty else { return entries }
        let q = searchText.lowercased()
        return entries.filter {
            (($0.content.value as? String) ?? "").lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }
    @Environment(\.dismiss) private var dismiss

    private let green = Color(hex: "#1E3932")
    private let gold  = Color(hex: "#CBA258")
    private let bg    = Color(hex: "#FAF7F2")

    private var companion: CompanionPersonality {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        NavigationView {
            ZStack {
                bg.ignoresSafeArea()

                if isLoading {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<7, id: \.self) { _ in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "#D4C9B4"))
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: "#D4C9B4"))
                                        .frame(height: 13)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: "#D4C9B4").opacity(0.6))
                                        .frame(width: 120, height: 11)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            Divider().padding(.leading, 60)
                        }
                    }
                    .shimmer()
                } else if entries.isEmpty {
                    emptyState
                } else {
                    memoriesList
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(green)
                }
            }
            .sheet(item: $editingEntry) { entry in
                MemoryEditSheet(entry: entry) { updated in
                    if let i = entries.firstIndex(where: { $0.id == updated.id }) {
                        entries[i] = updated
                    }
                    Task { try? await HermesMemory.shared.update(updated) }
                }
            }
            .confirmationDialog("Delete this memory?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let id = deleteTarget else { return }
                    entries.removeAll { $0.id == id }
                    Task { try? await HermesMemory.shared.delete(id: id) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
        }
        .task {
            entries = await HermesMemory.shared.recentEntries(limit: 80)
                .filter { !($0.content.value is NSNull) }
                .sorted { $0.timestamp > $1.timestamp }
            isLoading = false
        }
    }

    // MARK: – Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundColor(gold.opacity(0.7))
            Text("No memories yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(green)
            Text("\(companion.name) builds memories as you talk.\nEvery conversation adds to what they know about you.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#5C5C5C"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    // MARK: – Memories list

    private var memoriesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "#9A9A9A"))
                    TextField("Search memories…", text: $searchText)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Color(hex: "#2C1A0E"))
                        .submitLabel(.search)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#BBBBBB"))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(hex: "#F0EAE0"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

                // Header count
                Text("\(filteredEntries.count) thing\(filteredEntries.count == 1 ? "" : "s") \(companion.name) knows about you")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#9A9A9A"))
                    .tracking(0.3)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { i, entry in
                    memoryRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard entry.content.value is String else { return }
                            editingEntry = entry
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                BCHaptic.medium()
                                deleteTarget = entry.id
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                BCHaptic.light()
                                guard entry.content.value is String else { return }
                                editingEntry = entry
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color(hex: "#CBA258"))
                        }
                    if i < filteredEntries.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
        }
    }

    // MARK: – Memory row

    private func memoryRow(_ entry: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Category icon
            ZStack {
                Circle()
                    .fill(categoryColor(entry.category).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: categoryIcon(entry.category))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(categoryColor(entry.category))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(categoryLabel(entry.category))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(categoryColor(entry.category))
                        .tracking(0.5)
                    Spacer()
                    Text(entry.timestamp, style: .relative)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#BBBBBB"))
                    Text("ago")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#BBBBBB"))
                }

                Text(displayText(entry))
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#2A2A2A"))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Importance dots
                if entry.importance > 2 {
                    HStack(spacing: 3) {
                        ForEach(0..<entry.importance, id: \.self) { _ in
                            Circle()
                                .fill(gold.opacity(0.7))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: – Helpers

    private func displayText(_ entry: MemoryEntry) -> String {
        switch entry.content.value {
        case let s as String:  return s
        case let d as Double:  return String(d)
        case let i as Int:     return String(i)
        case let b as Bool:    return b ? "Yes" : "No"
        case let a as [Any]:   return a.compactMap { "\($0)" }.joined(separator: ", ")
        default:               return entry.category.capitalized
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat.lowercased() {
        case let c where c.contains("dream"):   return "moon.stars.fill"
        case let c where c.contains("emotion"): return "heart.fill"
        case let c where c.contains("interest"): return "star.fill"
        case let c where c.contains("fact"):    return "person.fill"
        case let c where c.contains("stress"):  return "bolt.fill"
        case let c where c.contains("goal"):    return "flag.fill"
        case let c where c.contains("humor"):   return "face.smiling.fill"
        case let c where c.contains("topic"):   return "bubble.left.fill"
        default:                                return "sparkle"
        }
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat.lowercased() {
        case let c where c.contains("dream"):   return Color(hex: "#7B68EE")
        case let c where c.contains("emotion"): return Color(hex: "#E85D75")
        case let c where c.contains("interest"): return Color(hex: "#CBA258")
        case let c where c.contains("fact"):    return Color(hex: "#1E3932")
        case let c where c.contains("stress"):  return Color(hex: "#E07B3A")
        case let c where c.contains("goal"):    return Color(hex: "#2E8B57")
        default:                                return Color(hex: "#5C5C5C")
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        cat.components(separatedBy: CharacterSet(charactersIn: "_-"))
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - MemoryEditSheet

struct MemoryEditSheet: View {
    let entry: MemoryEntry
    let onSave: (MemoryEntry) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    private let green = Color(hex: "#1E3932")
    private let gold  = Color(hex: "#CBA258")

    init(entry: MemoryEntry, onSave: @escaping (MemoryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: (entry.content.value as? String) ?? "")
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit what \(companionName) knows")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#9A9A9A"))
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                TextEditor(text: $text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#2A2A2A"))
                    .padding(12)
                    .background(Color(hex: "#F2F0EB"))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 120)

                Text("This memory shapes how \(companionName) understands you. Edit to correct errors or add clarity.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#AAAAAA"))
                    .padding(.horizontal, 20)

                Spacer()
            }
            .background(Color(hex: "#FAF7F2").ignoresSafeArea())
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(hex: "#9A9A9A"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        BCHaptic.medium()
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let updated = MemoryEntry(
                            id: entry.id,
                            timestamp: entry.timestamp,
                            category: entry.category,
                            content: cleaned,
                            metadata: entry.metadata.mapValues { $0.value },
                            importance: entry.importance,
                            tier: entry.tier
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(green)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var companionName: String {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id)?.name ?? "your companion"
    }
}
