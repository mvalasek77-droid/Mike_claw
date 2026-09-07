import Foundation
import Combine

/// Watches a `SwarmClient` for ship-stage progress and surfaces the
/// last seen line per phase. The strip in BuildScreen reads from this —
/// keeping the parsing out of the view keeps the view dumb and the
/// model testable.
///
/// This covers packaging as well as upload. To the user those are one
/// wait, and packaging is by far the longer half: an archive runs for
/// minutes, so if only upload were tracked the strip would stay hidden
/// through the slowest part of shipping and the app would look frozen
/// exactly when it is working hardest.
@MainActor
final class UploadProgressTracker: ObservableObject {
    /// Raw values match the `phase` the backend puts on its events.
    enum Phase: String, Hashable {
        case archive, export, validate, upload

        /// What to call it in front of someone shipping their first app.
        var title: String {
            switch self {
            case .archive:  "Building your app"
            case .export:   "Signing your app"
            case .validate: "Checking it with Apple"
            case .upload:   "Sending it to TestFlight"
            }
        }
    }

    @Published private(set) var phase: Phase?
    @Published private(set) var latestLine: String?
    @Published private(set) var lineCount: Int = 0
    /// True once shipping has stopped for good — either the upload
    /// reported its outcome, or packaging failed and no upload will
    /// follow. Flips the strip from spinning to a final-state look.
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
            case "testflight.package":
                if let raw = event.payload["phase"] as? String,
                   let parsed = Phase(rawValue: raw) {
                    p = parsed
                }
                // `ok` is null while packaging is still running, so a
                // missing Bool means "started", not "succeeded". Only a
                // literal false ends the run here; a true is followed by
                // the upload, which reports the real outcome.
                if (event.payload["ok"] as? Bool) == false {
                    done = true
                    success = false
                }
            case "testflight.package.progress":
                if let l = event.payload["line"] as? String, !l.isEmpty {
                    line = l
                    count += 1
                }
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
