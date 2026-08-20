import SwiftUI

struct ReportSheet: View {
    let kind: ContentReport.TargetKind
    let targetId: String
    let authorHandle: String
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .spam
    @State private var note: String = ""
    @State private var alsoBlock: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Reports are reviewed by BoxCall. Repeat offenders lose posting privileges. In the meantime, we'll hide this from your view.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in
                            Text(r.display).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Optional note") {
                    TextField("Anything the mod team should know", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Toggle("Also block @\(authorHandle)", isOn: $alsoBlock)
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        Text("Submit report")
                            .frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func submit() {
        ModerationService.shared.report(
            kind: kind, id: targetId, reason: reason,
            note: note.isEmpty ? nil : note
        )
        if alsoBlock {
            ModerationService.shared.block(handle: authorHandle)
        }
        dismiss()
    }
}
