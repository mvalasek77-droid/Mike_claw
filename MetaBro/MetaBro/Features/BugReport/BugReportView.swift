import SwiftUI

/// Lets a bro report a problem, automatically attaching device + recent-log
/// diagnostics so engineering doesn't have to ask "what happened, on what?"
struct BugReportView: View {
    @State private var model: BugReportViewModel
    @Environment(\.dismiss) private var dismiss

    init(service: BugReportService) {
        _model = State(initialValue: BugReportViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    TextField("Summary", text: $model.summary)
                    TextEditor(text: $model.details)
                        .frame(minHeight: 120)
                }
                Section("Severity") {
                    Picker("Severity", selection: $model.severity) {
                        ForEach(BugSeverity.allCases, id: \.self) { severity in
                            Text(severity.label).tag(severity)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Include device & log diagnostics", isOn: $model.includeDiagnostics)
                    if model.includeDiagnostics, let diagnostics = model.diagnostics {
                        diagnosticsPreview(diagnostics)
                    }
                } footer: {
                    Text("Diagnostics include your app version, device model, and the last few minutes of in-app activity — never your messages or post content.")
                }
                Section {
                    submitControl
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await model.loadDiagnostics() }
            .onChange(of: model.submitState) { _, newValue in
                if newValue == .success { dismiss() }
            }
        }
    }

    private func diagnosticsPreview(_ diagnostics: DeviceDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(diagnostics.deviceModel) · iOS \(diagnostics.osVersion)")
            Text("MetaBro \(diagnostics.appVersion) (\(diagnostics.buildNumber))")
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(Tokens.Color.textSecondary)
    }

    @ViewBuilder
    private var submitControl: some View {
        switch model.submitState {
        case .idle, .success:
            Button("Submit report") { Task { await model.submit() } }
                .disabled(!model.canSubmit)
        case .submitting:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text(message)
                    .foregroundStyle(.red)
                    .font(Tokens.Typography.caption)
                Button("Try again") { Task { await model.submit() } }
                    .disabled(!model.canSubmit)
            }
        }
    }
}
