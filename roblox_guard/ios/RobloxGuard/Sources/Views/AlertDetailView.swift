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

            Section("What we observed") {
                ForEach(alert.facts, id: \.self) { fact in
                    Label(fact, systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
            }

            Section("What you can do") {
                Text(alert.guidance)
                    .font(.subheadline)
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
                        await store.acknowledge(alert, for: child)
                        dismiss()
                    }
                } label: {
                    Label("Mark as handled", systemImage: "checkmark.circle")
                }
            }
        }
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
    }
}
