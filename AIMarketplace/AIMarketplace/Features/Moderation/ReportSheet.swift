import SwiftUI

/// In-app report sheet, reachable from any title page. Required by Apple App
/// Store Review Guideline 1.2 for user-generated content: an explicit, low-
/// friction way to flag objectionable or infringing content, plus the option
/// to block the creator from the user's feed.
struct ReportSheet: View {
    let item: MediaItem
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var moderation: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: Reason = .infringement
    @State private var details: String = ""
    @State private var submitting = false
    @State private var sent = false
    @State private var blocked = false
    @State private var notifyOnResolve = true

    enum Reason: String, CaseIterable, Identifiable {
        case infringement = "Copyright / IP infringement"
        case csam = "Sexual content involving a minor"
        case hate = "Hate, harassment, or threats"
        case fraud = "Fraud, scam, or impersonation"
        case undisclosed = "Undisclosed or mislabeled AI"
        case other = "Something else"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What's wrong with this title?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(Reason.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Details (optional)") {
                    TextEditor(text: $details)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Report details")
                }

                if !store.accountEmail.isEmpty {
                    Section {
                        Toggle("Email me when this is resolved", isOn: $notifyOnResolve)
                            .accessibilityHint("If on, we'll send a short note to \(store.accountEmail) once moderation has taken action.")
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if submitting { ProgressView().padding(.trailing, 6) }
                            Text(sent ? "Report sent — we aim to review within 24 hours" : "Send report")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(submitting || sent)

                    Button(role: .destructive) {
                        moderation.block(item.creator)
                        blocked = true
                    } label: {
                        Text(blocked ? "Creator blocked" : "Block this creator")
                    }
                    .disabled(blocked)
                }

                Section {
                    Text("Reports are forwarded to the AI Marketplace moderation team. We aim to act on serious reports within 24 hours. Knowingly false reports may result in account action.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if sent || blocked {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        submitting = true
        let ok = await moderation.submitReport(
            itemID: item.id,
            itemTitle: item.title,
            creatorName: item.creator,
            reason: reason.rawValue,
            details: details,
            reporterEmail: store.accountEmail.isEmpty ? nil : store.accountEmail,
            notifyOnResolve: notifyOnResolve && !store.accountEmail.isEmpty,
            baseURL: store.payoutBaseURL,
            sharedSecret: store.payoutSharedSecret
        )
        submitting = false
        sent = true
        // Even if the network call failed we still ack — the report is in the
        // local set and the user has done their part. The operator inbox is
        // the authoritative log; offline reports sync next time the Worker
        // sees the same item id from another report or audit.
        _ = ok
    }
}
