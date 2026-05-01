import SwiftUI

// MARK: - DreamEntry

struct DreamEntry: Codable, Identifiable {
    let id:   UUID
    let date: Date
    var text: String

    init(text: String) {
        self.id   = UUID()
        self.date = Date()
        self.text = text
    }

    var title: String {
        let first = text.components(separatedBy: .newlines).first ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Dream" : String(trimmed.prefix(52))
    }
}

// MARK: - DreamStore

@MainActor
final class DreamStore: ObservableObject {
    @Published var entries: [DreamEntry] = []

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dream_journal.json")
    }()

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([DreamEntry].self, from: data)
        else { return }
        entries = decoded.sorted { $0.date > $1.date }
    }

    func add(_ text: String) {
        let entry = DreamEntry(text: text)
        entries.insert(entry, at: 0)
        save()
        Task {
            // Feed into companion memory so it can reference dreams organically
            _ = try? await HermesMemory.shared.observe(
                category: "dream",
                content: text,
                metadata: ["date": ISO8601DateFormatter().string(from: entry.date)]
            )
            let persona = UserPersona.load()
            persona.learn(key: "dream_journal.last_entry", value: text)
            // Count as a meaningful personal share in the learning engine
            // — triggers emotional pattern detection + intimacy gain.
            // Dreams that contain emotional language ("scared", "afraid", "love")
            // score higher automatically via assessMessageQuality.
            await HerLearningEngine.shared.processUserMessage(
                text,
                responseText: "I love that you shared that with me.",
                interests: persona.interests
            )
            // Dreams deepen the romantic arc only when the user chose that mode.
            if persona.relationshipMode.allowsRomanticLoveArc {
                LoveEngine.shared.signal(.deepConversation)
            }
        }
    }

    func delete(_ entry: DreamEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}

// MARK: - DreamJournalView

struct DreamJournalView: View {

    @StateObject private var store = DreamStore()
    @State private var showAdd    = false
    @State private var newText    = ""
    @Environment(\.dismiss) private var dismiss

    private let green  = Color(hex: "#1E3932")
    private let purple = Color(hex: "#7B68EE")
    private let bg     = Color(hex: "#F2F0EB")

    var body: some View {
        NavigationView {
            ZStack {
                bg.ignoresSafeArea()

                if store.entries.isEmpty && !showAdd {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if showAdd { addEntryCard }

                            ForEach(store.entries) { entry in
                                dreamRow(entry)
                                Divider().padding(.leading, 20)
                            }
                        }
                        .padding(.top, showAdd ? 0 : 16)
                    }
                }
            }
            .navigationTitle("Dream Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(green)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showAdd = true
                            newText = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(purple)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: – Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 52))
                .foregroundColor(purple.opacity(0.7))
            Text("No dreams logged yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(green)
            Text("Tap + to record your first dream.\nYour companion can reference your dreams in conversation.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#5C5C5C"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Button {
                withAnimation { showAdd = true }
            } label: {
                Text("Log a dream")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(purple)
                    .cornerRadius(24)
            }
            .padding(.top, 4)
        }
    }

    // MARK: – Add entry card

    private var addEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What did you dream?")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#5C5C5C"))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            TextEditor(text: $newText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1E3932"))
                .frame(minHeight: 120)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(12)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    withAnimation { showAdd = false; newText = "" }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "#5C5C5C"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(12)
                }

                Button {
                    let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    store.add(t)
                    withAnimation { showAdd = false; newText = "" }
                } label: {
                    Text("Save Dream")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? purple.opacity(0.4) : purple)
                        .cornerRadius(12)
                }
                .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(hex: "#EDE9F8"))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: – Dream row

    private func dreamRow(_ entry: DreamEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 16))
                    .foregroundColor(purple.opacity(0.8))
                Text(dayLabel(entry.date))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#5C5C5C"))
            }
            .frame(width: 36)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(green)
                    .lineLimit(1)
                Text(entry.date, style: .date)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#9A9A9A"))
                if entry.text.count > entry.title.count + 2 {
                    Text(entry.text)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#5C5C5C"))
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Button {
                withAnimation { store.delete(entry) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#BBBBBB"))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM\ndd"
        return fmt.string(from: date)
    }
}
