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

        case "xcodebuild":
            return try await runXcodeBuild(payload: payload, requestID: requestID, send: send)

        case "screenshot":
            return try await screenshot(display: payload["display"] as? Int ?? 0)

        case "app_store_connect.fill":
            // Stub for now — real impl drives Safari via AppleScript and
            // requires a per-call Mac confirmation banner.
            throw CmdError.bad("app_store_connect.fill not yet implemented")

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
