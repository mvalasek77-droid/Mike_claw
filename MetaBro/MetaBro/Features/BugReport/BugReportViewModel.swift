import SwiftUI

@MainActor
@Observable
final class BugReportViewModel {
    enum SubmitState: Equatable {
        case idle
        case submitting
        case success
        case failed(String)
    }

    var summary: String = ""
    var details: String = ""
    var severity: BugSeverity = .minor
    var includeDiagnostics: Bool = true
    private(set) var submitState: SubmitState = .idle
    private(set) var diagnostics: DeviceDiagnostics?

    private let service: BugReportService

    init(service: BugReportService) {
        self.service = service
    }

    var canSubmit: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && submitState != .submitting
    }

    func loadDiagnostics() async {
        diagnostics = await service.diagnostics()
    }

    func submit() async {
        guard canSubmit else { return }
        submitState = .submitting
        let draft = BugReportDraft(
            summary: summary,
            details: details,
            severity: severity,
            includeDiagnostics: includeDiagnostics
        )
        do {
            try await service.submit(draft)
            submitState = .success
            HapticsEngine.shared.play(.refreshDone)
        } catch {
            BroLog.error(error, category: "bugReport")
            submitState = .failed("Couldn't send your report. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
        }
    }
}
