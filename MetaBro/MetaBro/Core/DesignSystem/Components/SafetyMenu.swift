import SwiftUI

/// The "report / block / mute" overflow menu, shared by posts, comments,
/// profiles, and DMs so safety actions look and behave the same everywhere.
/// Reporting opens a reason sheet; block/mute fire immediately (both are
/// reversible from the blocked/muted list in Settings).
struct SafetyMenu: View {
    let user: User
    let kind: ReportedContentKind
    let targetID: UUID
    let preview: String
    var community: Community? = nil
    let service: SafetyService

    @State private var isReportSheetPresented = false
    @State private var lastAction: String?

    var body: some View {
        Menu {
            Button { isReportSheetPresented = true } label: {
                Label("Report", systemImage: "flag")
            }
            Button(role: .destructive) { Task { await mute() } } label: {
                Label("Mute \(user.displayName)", systemImage: "speaker.slash")
            }
            Button(role: .destructive) { Task { await block() } } label: {
                Label("Block \(user.displayName)", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Tokens.Color.textSecondary)
        }
        .accessibilityLabel("More options")
        .sheet(isPresented: $isReportSheetPresented) {
            ReportSheet(user: user, kind: kind, targetID: targetID, preview: preview,
                        community: community, service: service)
        }
        .overlay(alignment: .top) {
            if let lastAction {
                Text(lastAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tokens.Color.accent, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .offset(y: -36)
                    .allowsHitTesting(false)
            }
        }
        .animation(Tokens.Motion.gentle, value: lastAction)
    }

    private func mute() async {
        HapticsEngine.shared.play(.selectionChanged)
        do {
            try await service.mute(user)
            lastAction = "\(user.displayName) muted"
            dismissConfirmation()
        } catch { BroLog.error(error, category: "safety") }
    }

    private func block() async {
        HapticsEngine.shared.play(.selectionChanged)
        do {
            try await service.block(user)
            lastAction = "\(user.displayName) blocked"
            dismissConfirmation()
        } catch { BroLog.error(error, category: "safety") }
    }

    private func dismissConfirmation() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            lastAction = nil
        }
    }
}

/// Pick a reason (+ optional details) and file the report. Self-contained so
/// any feature can present it as a sheet without its own view model.
struct ReportSheet: View {
    let user: User
    let kind: ReportedContentKind
    let targetID: UUID
    let preview: String
    var community: Community? = nil
    let service: SafetyService

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases, id: \.self) { reason in
                            Text(reason.label).tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Additional details (optional)") {
                    TextField("Anything mods should know…", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(isSubmitting)
                }
            }
            .disabled(didSubmit)
            .overlay {
                if didSubmit {
                    ContentUnavailableView("Report submitted",
                                           systemImage: "checkmark.circle.fill",
                                           description: Text("Mods will take a look."))
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.report(kind: kind, targetID: targetID, preview: preview,
                                      reportedUser: user, community: community,
                                      reason: reason,
                                      details: details.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            HapticsEngine.shared.play(.refreshDone)
            didSubmit = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            BroLog.error(error, category: "safety")
            HapticsEngine.shared.play(.error)
        }
    }
}
