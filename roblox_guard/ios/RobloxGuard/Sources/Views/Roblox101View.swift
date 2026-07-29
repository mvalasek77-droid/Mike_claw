import SwiftUI

/// From-zero Roblox explainer for parents who have never used the platform.
/// Content is served by the backend so it can be improved without app updates.
struct Roblox101View: View {
    @EnvironmentObject var store: Store
    @State private var content: EducationContent?

    var body: some View {
        List {
            if let content {
                Section {
                    Text("Never used Roblox? Start here. Five minutes of reading covers everything this app will ever mention.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(content.robloxBasics) { entry in
                        DisclosureGroup {
                            Text(entry.answer)
                                .font(.subheadline)
                                .padding(.top, 2)
                        } label: {
                            Text(entry.question)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                } header: {    Text("The basics")}

                Section {
                    ForEach(content.glossary, id: \.term) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.definition)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {    Text("Every term, explained")}
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle("Roblox 101")
        .task {
            content = try? await store.education()
        }
    }
}
