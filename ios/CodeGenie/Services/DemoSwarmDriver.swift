import Foundation

/// Replays a canned `DemoScript-<id>.json` into a `SwarmClient` so the
/// BuildScreen renders a magical, complete-looking build without
/// touching the backend or burning a single token.
///
/// This is the **first-time user experience.** They see the real
/// product — same transcript, same cost meter, same diff stream,
/// same success overlay — in 30 seconds.
@MainActor
enum DemoSwarmDriver {

    /// Start replaying the script with `sampleID` into `client`.
    /// Returns immediately; emission continues on a background task
    /// until the last frame's `after_ms` elapses.
    @discardableResult
    static func play(into client: SwarmClient, sampleID: String) -> Bool {
        guard let frames = loadScript(sampleID: sampleID), !frames.isEmpty else {
            return false
        }

        client.setDemoState(jobID: "demo_\(sampleID)", connected: true)

        Task { @MainActor in
            for frame in frames {
                try? await Task.sleep(nanoseconds: UInt64(frame.afterMS) * 1_000_000)
                let event = SwarmEvent(
                    type: frame.type,
                    ts: Date().timeIntervalSince1970,
                    jobID: "demo_\(sampleID)",
                    agent: frame.agent,
                    payload: frame.payload
                )
                client.pushDemoEvent(event)
            }
            client.setDemoState(jobID: "demo_\(sampleID)", connected: false)
        }
        return true
    }

    // MARK: - Loading

    private struct Frame {
        let afterMS: Int
        let type: String
        let agent: String?
        let payload: [String: Any]
    }

    private static func loadScript(sampleID: String) -> [Frame]? {
        let name = "DemoScript-\(sampleID)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFrames = json["frames"] as? [[String: Any]] else { return nil }
        return rawFrames.compactMap { dict in
            guard let after = dict["after_ms"] as? Int,
                  let type  = dict["type"] as? String else { return nil }
            return Frame(
                afterMS: after,
                type: type,
                agent: dict["agent"] as? String,
                payload: (dict["payload"] as? [String: Any]) ?? [:]
            )
        }
    }
}
