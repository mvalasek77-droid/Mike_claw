import SwiftUI

// MARK: - MemoriesView
//
// Displays memories the companion has formed about you.
// Backed by HermesMemory — the same system the companion uses
// when building context for every conversation.

struct MemoriesView: View {

    @State private var entries:   [MemoryEntry] = []
    @State private var isLoading: Bool = true
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
                    ProgressView()
                        .tint(green)
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
        }
        .preferredColorScheme(.light)
        .task {
            entries = await HermesMemory.shared.recentEntries(limit: 80)
                .filter { !($0.content.value is NSNull) }
                .sorted { $0.date > $1.date }
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
                // Header count
                Text("\(entries.count) thing\(entries.count == 1 ? "" : "s") \(companion.name) knows about you")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#9A9A9A"))
                    .tracking(0.3)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    memoryRow(entry)
                    if i < entries.count - 1 {
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
                    Text(entry.date, style: .relative)
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
