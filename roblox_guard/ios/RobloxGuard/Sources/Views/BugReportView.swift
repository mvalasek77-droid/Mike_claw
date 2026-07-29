import SwiftUI
import UIKit

/// "Report a Bug" (Settings → Support). Two independent delivery paths on
/// purpose: submitting here writes to the backend's durable bug log (visible
/// to the operator at GET /support/bug-reports, emailed if SMTP is
/// configured) — but if the backend itself is unreachable, that's exactly
/// when a parent most needs to reach us, so a direct mailto: link to the
/// support address always works regardless of backend or network state.
struct BugReportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    static let supportEmail = "mvalasek@gmail.com"

    @State private var summary = ""
    @State private var details = ""
    @State private var contactEmail = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var didSubmit = false

    private var canSubmit: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                if didSubmit {
                    Section {
                        Label("Thanks — this was logged for the team to review.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    TextField("Short summary, e.g. \"Alerts don't refresh\"", text: $summary)
                    TextField("Details (optional): what you were doing, what you expected",
                              text: $details, axis: .vertical)
                        .lineLimit(4...8)
                } header: {    Text("What went wrong?")}  footer: {
                    Text("Never include your child's Roblox password or private chat content — this app never asks for either.")
                }

                Section {
                    TextField("Your email", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {    Text("Hear back (optional)")}

                if let submitError {
                    Section {
                        Text(submitError).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        emailDirectly()
                    } label: {
                        Label("Email us directly instead", systemImage: "envelope")
                    }
                } footer: {
                    Text("Opens Mail addressed to \(Self.supportEmail) — works even if the app can't reach our servers.")
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(didSubmit ? "Done" : "Submit") {
                        if didSubmit {
                            dismiss()
                        } else {
                            submit()
                        }
                    }
                    .disabled(!didSubmit && !canSubmit)
                }
            }
        }
    }

    private func submit() {
        Task {
            isSubmitting = true
            submitError = nil
            if store.isDemoMode {
                Haptics.success()
                didSubmit = true
                isSubmitting = false
                return
            }
            do {
                try await store.api.submitBugReport(
                    summary: summary.trimmingCharacters(in: .whitespaces),
                    details: details.trimmingCharacters(in: .whitespaces),
                    contactEmail: contactEmail.trimmingCharacters(in: .whitespaces)
                )
                Haptics.success()
                didSubmit = true
            } catch {
                submitError = "Couldn't reach our server (\(error.localizedDescription)). Try \"Email us directly\" below instead."
            }
            isSubmitting = false
        }
    }

    private func emailDirectly() {
        let device = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(UIDevice.current.model)"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        var body = ""
        if !summary.isEmpty { body += "Summary: \(summary)\n" }
        if !details.isEmpty { body += "Details: \(details)\n" }
        body += "\nApp version: \(version)\nDevice: \(device)"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "RobloxGuard bug report"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}
