import Foundation

/// Allow-listed command handlers.
///
/// New commands MUST be added here explicitly — there is no generic
/// "shell" command. Each handler returns a JSON-encodable dictionary
/// that becomes the response payload, or throws to surface an error.
final class Commands {
    static let shared = Commands()

    typealias EventSender = ([String: Any]) -> Void

    func handle(
        type: String,
        payload: [String: Any],
        requestID: String,
        send: @escaping EventSender
    ) async throws -> [String: Any] {
        switch type {
        case "ping":
            return ["pong": true]

        case "open_xcode_project":
            guard let path = payload["path"] as? String else { throw CmdError.bad("path missing") }
            try requireExists(path)
            try await runApp(["/usr/bin/open", "-a", "Xcode", path])
            return ["opened": path]

        case "open_safari":
            guard let url = payload["url"] as? String else { throw CmdError.bad("url missing") }
            var args = ["/usr/bin/open", "-a", "Safari", url]
            if (payload["new_window"] as? Bool) == true { args.insert("-n", at: 1) }
            try await runApp(args)
            return ["opened": url]

        case "open_url":
            guard let url = payload["url"] as? String else { throw CmdError.bad("url missing") }
            guard isAllowedURL(url) else { throw CmdError.bad("url scheme not allowed") }
            try await runApp(["/usr/bin/open", url])
            return ["opened": url]

        case "xcodebuild":
            return try await runXcodeBuild(payload: payload, requestID: requestID, send: send)

        case "screenshot":
            return try await screenshot(display: payload["display"] as? Int ?? 0)

        case "app_store_connect.fill":
            return try await fillAppStoreConnect(payload: payload)

        default:
            throw CmdError.bad("unknown command: \(type)")
        }
    }

    // MARK: Helpers

    private func requireExists(_ path: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw CmdError.bad("path does not exist: \(path)")
        }
    }

    private func runApp(_ argv: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: argv[0])
        process.arguments = Array(argv.dropFirst())
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CmdError.bad("\(argv[0]) exited \(process.terminationStatus)")
        }
    }

    private func isAllowedURL(_ raw: String) -> Bool {
        guard let scheme = URLComponents(string: raw)?.scheme?.lowercased() else { return false }
        return ["https", "http", "macappstores"].contains(scheme)
    }

    private func runXcodeBuild(
        payload: [String: Any],
        requestID: String,
        send: @escaping EventSender
    ) async throws -> [String: Any] {
        let scheme = (payload["scheme"] as? String) ?? "App"
        let action = (payload["action"] as? String) ?? "build"
        let dest   = (payload["destination"] as? String) ?? "platform=iOS Simulator,name=iPhone 16"
        let proj   = (payload["workspace_or_project"] as? String) ?? ""
        try requireExists(proj)
        let flag = proj.hasSuffix(".xcworkspace") ? "-workspace" : "-project"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [
            flag, proj, "-scheme", scheme,
            "-destination", dest, action,
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        try process.run()

        var tail: [String] = []
        let handle = pipe.fileHandleForReading
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                while process.isRunning || handle.availableData.count > 0 {
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        Thread.sleep(forTimeInterval: 0.1)
                        continue
                    }
                    if let s = String(data: chunk, encoding: .utf8) {
                        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
                            let line = String(raw)
                            send([
                                "v": 1, "kind": "event", "in_response_to": requestID,
                                "type": "xcodebuild.line",
                                "payload": ["line": line],
                            ])
                            tail.append(line)
                            if tail.count > 200 { tail.removeFirst(tail.count - 200) }
                        }
                    }
                }
                continuation.resume()
            }
        }
        process.waitUntilExit()
        return [
            "exit_code": Int(process.terminationStatus),
            "log_tail": tail.joined(separator: "\n"),
        ]
    }

    /// Drives the frontmost Safari window via AppleScript / JS to fill
    /// an App Store Connect form field.
    ///
    /// Workflow per call:
    ///   1. Display a system notification on the Mac asking the user
    ///      to confirm (`Approve` / `Reject` buttons via osascript).
    ///   2. If approved, run a JavaScript snippet against the active
    ///      Safari tab that sets the value of the named field and
    ///      dispatches an `input` event so React-style listeners fire.
    ///
    /// This is intentionally narrow — we only target App Store Connect
    /// because we know the field selectors; on other domains the
    /// command refuses.
    private func fillAppStoreConnect(payload: [String: Any]) async throws -> [String: Any] {
        guard let field = payload["field"] as? String,
              let value = payload["value"] as? String else {
            throw CmdError.bad("field + value required")
        }

        // Always confirm with the human in the loop.
        let approved = try await askUserApproval(title: "CodeGenie wants to fill", message: "\(field) → \(value)")
        guard approved else {
            return ["filled": false, "reason": "user rejected"]
        }

        // Verify we're on appstoreconnect.apple.com — we won't drive
        // arbitrary websites.
        let urlScript = """
        tell application "Safari"
          if (count of windows) is 0 then return "(no window)"
          return URL of current tab of front window
        end tell
        """
        let currentURL = (try await runOsa(urlScript)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentURL.contains("appstoreconnect.apple.com") else {
            throw CmdError.bad("Safari isn't on App Store Connect (saw: \(currentURL))")
        }

        // Set the field. We try several selector strategies because
        // ASC's Vue/React stack uses different attribute schemes per
        // page. Order: data-testid, name, aria-label, placeholder.
        let escapedField = jsEscape(field)
        let escapedValue = jsEscape(value)
        let js = """
        (function() {
          const sel = [
            '[data-testid="' + #field + '"]',
            'input[name="' + #field + '"]',
            'textarea[name="' + #field + '"]',
            '[aria-label="' + #field + '"]',
            'input[placeholder="' + #field + '"]'
          ].map(s => s.replace(/#field/g, '\(escapedField)'));
          for (const q of sel) {
            const el = document.querySelector(q);
            if (el) {
              const setter = Object.getOwnPropertyDescriptor(el.__proto__, 'value').set;
              setter.call(el, '\(escapedValue)');
              el.dispatchEvent(new Event('input',  { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              return 'OK ' + q;
            }
          }
          return 'NOT_FOUND';
        })();
        """
        let escapedJS = js.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let runScript = """
        tell application "Safari"
          do JavaScript "\(escapedJS)" in current tab of front window
        end tell
        """
        let result = (try await runOsa(runScript)).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("OK ") {
            return ["filled": true, "selector": String(result.dropFirst(3))]
        } else {
            throw CmdError.bad("could not find field '\(field)' on the current page")
        }
    }

    private func askUserApproval(title: String, message: String) async throws -> Bool {
        let osa = """
        display dialog "\(message)" with title "\(title)" buttons {"Reject", "Approve"} default button "Approve"
        """
        do {
            let out = try await runOsa(osa)
            return out.contains("Approve")
        } catch {
            return false
        }
    }

    private func runOsa(_ script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw CmdError.bad("osascript exit \(process.terminationStatus): \(text)")
        }
        return text
    }

    private func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'",  with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func screenshot(display: Int) async throws -> [String: Any] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cg-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-D", "\(display + 1)", "-x", tmp.path]
        try process.run()
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard process.terminationStatus == 0 else {
            throw CmdError.bad("screencapture exited \(process.terminationStatus)")
        }
        let data = try Data(contentsOf: tmp)
        return ["image_b64": data.base64EncodedString()]
    }
}

enum CmdError: Error, CustomStringConvertible {
    case bad(String)
    var description: String {
        switch self { case .bad(let s): return s }
    }
}
