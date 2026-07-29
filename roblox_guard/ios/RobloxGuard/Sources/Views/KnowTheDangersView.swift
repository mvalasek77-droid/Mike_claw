import SwiftUI

/// Parent education: the danger catalog, behavioral warning signs, immediate
/// red flags, and the response playbook — served from the backend so content
/// updates don't require an app release.
struct KnowTheDangersView: View {
    @EnvironmentObject var store: Store
    @State private var content: EducationContent?

    var body: some View {
        List {
            if let content {
                Section {
                    Text("How targeting works on Roblox, what to watch for, and exactly what to do. Knowing the pattern is the best protection there is.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(content.dangers) { danger in
                        DisclosureGroup {
                            Text(danger.summary)
                                .font(.subheadline)
                            if !danger.progression.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("How it typically unfolds:")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(Array(danger.progression.enumerated()), id: \.offset) { index, step in
                                        Text("\(index + 1). \(step)")
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        } label: {
                            Text(danger.title)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                } header: {    Text("The dangers")}

                Section {
                    ForEach(content.behavioralSigns, id: \.self) { sign in
                        Label { Text(sign).font(.subheadline) }
                            icon: { Image(systemName: "eye").foregroundStyle(.orange) }
                    }
                } header: {    Text("Signs only you can see at home")}

                Section {
                    ForEach(content.immediateRedFlags, id: \.self) { flag in
                        Label { Text(flag).font(.subheadline) }
                            icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    }
                } header: {
                    Text("Act the same day if any of these happened")
                }

                Section {
                    ForEach(Array(content.responsePlaybook.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            Text(step).font(.subheadline)
                        }
                    }
                } header: {    Text("If something has happened: the playbook")}
            } else {
                ProgressView("Loading…")
            }
        }
        .navigationTitle("Know the Dangers")
        .task {
            content = try? await store.education()
        }
    }
}
