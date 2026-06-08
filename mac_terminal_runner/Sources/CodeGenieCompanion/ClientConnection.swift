import Foundation
import Network

/// One attached iPhone. Owns the framing reader, dispatches messages
/// to the command handler, and writes responses back.
final class ClientConnection {
    let id: UUID
    private let conn: NWConnection
    private let expectedToken: String
    private let onClose: () -> Void
    private let queue = DispatchQueue(label: "com.codegenie.terminal-runner.client")
    private var authenticated: Bool = false

    init(id: UUID, conn: NWConnection, token: String, onClose: @escaping () -> Void) {
        self.id = id
        self.conn = conn
        self.expectedToken = token
        self.onClose = onClose
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readNext()
            case .failed, .cancelled:
                self?.close()
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func close() {
        conn.cancel()
        onClose()
    }

    // MARK: Read loop

    private func readNext() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("terminal runner read error: \(error)")
                self.close()
                return
            }
            if let data, !data.isEmpty {
                self.handle(payload: data)
            }
            if isComplete {
                self.close()
            } else {
                self.readNext()
            }
        }
    }

    private func handle(payload: Data) {
        // Newline-delimited JSON keeps the Terminal runner and iOS
        // `NWConnection` client on the same simple framing model.
        let text = String(data: payload, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            handle(message: json)
        }
    }

    // MARK: Dispatch

    private func handle(message: [String: Any]) {
        let type = (message["type"] as? String) ?? ""
        let id   = (message["id"] as? String) ?? UUID().uuidString
        let payload = (message["payload"] as? [String: Any]) ?? [:]

        if !authenticated {
            if type == "auth", let provided = payload["token"] as? String, provided == expectedToken {
                authenticated = true
                send(envelope: [
                    "v": 1, "kind": "response", "in_response_to": id, "ok": true,
                    "payload": ["authenticated": true]
                ])
            } else {
                send(envelope: [
                    "v": 1, "kind": "response", "in_response_to": id, "ok": false,
                    "error": "must authenticate first"
                ])
                close()
            }
            return
        }

        Task {
            do {
                let result = try await Commands.shared.handle(type: type, payload: payload, requestID: id, send: { event in
                    self.send(envelope: event)
                })
                self.send(envelope: [
                    "v": 1, "kind": "response", "in_response_to": id, "ok": true, "payload": result
                ])
            } catch {
                self.send(envelope: [
                    "v": 1, "kind": "response", "in_response_to": id, "ok": false,
                    "error": "\(error)"
                ])
            }
        }
    }

    // MARK: Send

    private func send(envelope: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        var line = data
        line.append(0x0A)  // newline
        conn.send(content: line, completion: .contentProcessed { err in
            if let err { NSLog("terminal runner send error: \(err)") }
        })
    }
}
