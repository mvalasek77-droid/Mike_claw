import Foundation
import Combine

/// Watches a `SwarmClient` for `testflight.upload.progress` events
/// and surfaces the last seen line per phase. The strip in BuildScreen
/// reads from this — keeping the parsing out of the view keeps the
/// view dumb and the model testable.
@MainActor
final class UploadProgressTracker: ObservableObject {
    enum Phase: String, Hashable {
        case validate, upload
    }

    @Published private(set) var phase: Phase?
    @Published private(set) var latestLine: String?
    @Published private(set) var lineCount: Int = 0
    /// True after a `testflight.upload` summary event has fired —
    /// used to flip the strip from spinning to a final-state look.
    @Published private(set) var finished: Bool = false
    @Published private(set) var ok: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        phase = nil; latestLine = nil; lineCount = 0
        finished = false; ok = false
        client.$events
            .sink { [weak self] events in self?.consume(events) }
            .store(in: &cancellables)
    }

    private func consume(_ events: [SwarmEvent]) {
        var p: Phase? = nil
        var line: String? = nil
        var count = 0
        var done = false
        var success = false
        for event in events {
            switch event.type {
            case "testflight.upload.progress":
                if let raw = event.payload["phase"] as? String,
                   let parsed = Phase(rawValue: raw) {
                    p = parsed
                }
                if let l = event.payload["line"] as? String, !l.isEmpty {
                    line = l
                    count += 1
                }
            case "testflight.upload":
                done = true
                success = (event.payload["ok"] as? Bool) ?? false
            default:
                continue
            }
        }
        phase = p
        latestLine = line
        lineCount = count
        finished = done
        ok = success
    }
}
