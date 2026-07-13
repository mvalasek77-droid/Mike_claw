import SwiftUI

struct AlertDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let child: Child
    let alert: SafetyAlert

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(alert.severity.label.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(alert.severity == .elevated ? .red :
                                         alert.severity == .watch ? .orange : .secondary)
                    Text(alert.title)
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(alert.facts, id: \.self) { fact in
                    Label(fact, systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
            } header: {
                Text("What we observed")
            } footer: {
                Text("This is a pattern match, not a conclusion — it can be a false positive, and a lack of alerts doesn't mean nothing is wrong. Use it as one input alongside talking to your child.")
            }

            Section("What you can do") {
                Text(alert.guidance)
                    .font(.subheadline)
            }

            if let explainers = alert.explainers, !explainers.isEmpty {
                Section("What these words mean") {
                    ForEach(explainers, id: \.term) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.definition)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Take action") {
                Link(destination: URL(string: "https://en.help.roblox.com/hc/en-us/articles/203312410")!) {
                    Label("Report to Roblox", systemImage: "flag")
                }
                Link(destination: URL(string: "https://report.cybertip.org")!) {
                    Label("NCMEC CyberTipline", systemImage: "phone.arrow.up.right")
                }
                if let username = alert.subjectUsername,
                   let url = URL(string: "https://www.roblox.com/search/users?keyword=\(username)") {
                    Link(destination: url) {
                        Label("View \(username) on Roblox", systemImage: "person.crop.circle")
                    }
                }
            }

            Section {
                Button {
                    Task {
                        try? await store.api.sendFeedback(alertId: alert.id, verdict: "confirmed")
                        await store.loadAll()
                        dismiss()
                    }
                } label: {
                    Label("This was a real problem", systemImage: "exclamationmark.bubble")
                        .foregroundStyle(.red)
                }
                Button {
                    Task {
                        try? await store.api.sendFeedback(alertId: alert.id, verdict: "dismissed")
                        await store.loadAll()
                        dismiss()
                    }
                } label: {
                    Label("Not relevant for us", systemImage: "hand.thumbsdown")
                }
                Button {
                    Task {
                        await store.acknowledge(alert, for: child)
                        Haptics.success()
                        dismiss()
                    }
                } label: {
                    Label("Mark as handled", systemImage: "checkmark.circle")
                }
            } header: {
                Text("Your verdict tunes future alerts")
            } footer: {
                Text("Confirming a real problem switches this child to heightened monitoring. Dismissing the same kind of alert three times mutes it — except top-severity alerts, which always come through.")
            }
        }
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
    }
}
