import SwiftUI

/// Triage pending reports for every Bro-hood the current user moderates.
/// Approve dismisses the report; remove takes it down (and, for repeat
/// offenders, bans the reported user from that report's community).
@MainActor
@Observable
final class ModQueueViewModel {
    enum State: Equatable {
        case loading
        case loaded([Report])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: ModerationService

    init(service: ModerationService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let reports = try await service.queue()
            state = reports.isEmpty ? .empty : .loaded(reports)
        } catch {
            BroLog.error(error, category: "moderation")
            state = .error("Couldn't load the mod queue.")
        }
    }

    func approve(_ report: Report) async {
        await act(report) { try await service.approve($0) }
    }

    func remove(_ report: Report) async {
        await act(report) { try await service.remove($0) }
    }

    func ban(_ report: Report) async {
        guard let community = report.community else { return }
        do {
            try await service.ban(report.reportedUser, from: community)
            HapticsEngine.shared.play(.refreshDone)
        } catch {
            BroLog.error(error, category: "moderation")
            HapticsEngine.shared.play(.error)
        }
        await act(report) { try await service.remove($0) }
    }

    /// Optimistically drops the report from the visible queue, then performs
    /// the matching service call, restoring it on failure.
    private func act(_ report: Report, _ operation: (Report) async throws -> Void) async {
        guard case .loaded(var reports) = state else { return }
        reports.removeAll { $0.id == report.id }
        state = reports.isEmpty ? .empty : .loaded(reports)
        HapticsEngine.shared.play(.selectionChanged)

        do {
            try await operation(report)
        } catch {
            BroLog.error(error, category: "moderation")
            await load()
            HapticsEngine.shared.play(.error)
        }
    }
}
