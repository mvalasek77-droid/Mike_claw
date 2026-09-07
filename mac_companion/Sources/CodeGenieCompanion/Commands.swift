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

        case "xcodebuild.archive_export":
            return try await archiveAndExport(payload: payload, requestID: requestID, send: send)

        case "asc.upload":
            return try await uploadToAppStore(payload: payload, requestID: requestID, send: send)

        case "workspace.fetch":
            return try await fetchWorkspace(payload: payload, requestID: requestID, send: send)

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

    // MARK: Archive + export
    //
    // This is the step that turns generated source into the one thing
    // Apple actually accepts: a signed .ipa. It is deliberately NOT
    // part of `runXcodeBuild`, which hardcodes CODE_SIGNING_ALLOWED=NO
    // for fast simulator builds — an unsigned archive cannot be
    // exported for the App Store, so the two paths must stay separate.
    //
    // Signing uses `-allowProvisioningUpdates` with the user's App
    // Store Connect API key. That lets Xcode create and download the
    // certificate and provisioning profile on its own, with no 2FA
    // prompt and nothing for the user to configure by hand.
    private func archiveAndExport(
        payload: [String: Any],
        requestID: String,
        send: @escaping EventSender
    ) async throws -> [String: Any] {
        let root = (payload["workspace_root"] as? String) ?? ""
        try requireExists(root)

        // Auto-detect rather than making the phone guess: only this
        // machine can see what the generated project actually is.
        let proj = try (payload["workspace_or_project"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? detectProject(in: root)
        try requireExists(proj)
        let scheme = try (payload["scheme"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? detectScheme(project: proj)

        let configuration = (payload["configuration"] as? String) ?? "Release"
        let teamID = (payload["team_id"] as? String) ?? ""
        let method = (payload["export_method"] as? String) ?? "app-store-connect"

        let work = URL(fileURLWithPath: root)
        let archivePath = work.appendingPathComponent("build/CodeGenie.xcarchive").path
        let exportPath  = work.appendingPathComponent("build/export").path
        let plistPath   = work.appendingPathComponent("build/ExportOptions.plist").path
        try? FileManager.default.createDirectory(
            at: work.appendingPathComponent("build"),
            withIntermediateDirectories: true
        )

        // The signing key arrives inline from the phone and must not
        // outlive this command. It is written owner-only, used, and
        // deleted however this function exits.
        let ephemeralKey = try ephemeralKeyFile(payload: payload)
        defer { discardKey(ephemeralKey) }

        let auth = authArgs(payload: payload, root: root, keyOverride: ephemeralKey)
        let flag = proj.hasSuffix(".xcworkspace") ? "-workspace" : "-project"

        // --- archive ---
        var archiveArgv = [
            flag, proj,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", "generic/platform=iOS",
            "-archivePath", archivePath,
            "archive",
            "-allowProvisioningUpdates",
        ]
        archiveArgv.append(contentsOf: auth)
        if !teamID.isEmpty { archiveArgv.append("DEVELOPMENT_TEAM=\(teamID)") }

        let archiveResult = try await streamXcodebuild(
            archiveArgv, phase: "archive", requestID: requestID, send: send
        )
        guard archiveResult.code == 0 else {
            return [
                "ok": false, "phase": "archive",
                "exit_code": Int(archiveResult.code),
                "log_tail": archiveResult.tail,
                "scheme": scheme, "project": proj,
            ]
        }

        // --- export options ---
        try writeExportOptions(path: plistPath, method: method, teamID: teamID)

        // --- export ---
        var exportArgv = [
            "-exportArchive",
            "-archivePath", archivePath,
            "-exportOptionsPlist", plistPath,
            "-exportPath", exportPath,
            "-allowProvisioningUpdates",
        ]
        exportArgv.append(contentsOf: auth)

        let exportResult = try await streamXcodebuild(
            exportArgv, phase: "export", requestID: requestID, send: send
        )
        guard exportResult.code == 0 else {
            return [
                "ok": false, "phase": "export",
                "exit_code": Int(exportResult.code),
                "log_tail": exportResult.tail,
            ]
        }

        guard let ipa = firstIPA(in: exportPath) else {
            return [
                "ok": false, "phase": "export",
                "exit_code": 0,
                "log_tail": "export reported success but no .ipa was produced in \(exportPath)",
            ]
        }

        // Hand back a workspace-relative path: the backend addresses
        // everything through its sandbox, which rejects absolute paths.
        let relative = ipa.hasPrefix(root)
            ? String(ipa.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : ipa
        return [
            "ok": true,
            "ipa_path": relative,
            "absolute_path": ipa,
            "scheme": scheme,
            "project": proj,
        ]
    }

    /// Validate then upload a signed `.ipa` to TestFlight.
    ///
    /// This runs here rather than on the build server because the
    /// signing key lives in the phone's Keychain and the user chose to
    /// keep it off any server. The phone hands it over the local
    /// connection, this writes it owner-only for the length of the
    /// upload, and deletes it on every exit path.
    ///
    /// Validate first: `altool` reports most rejections (wrong bundle
    /// ID, missing icon, bad entitlements) in seconds, and finding
    /// them before a multi-minute upload saves the user that wait.
    private func uploadToAppStore(
        payload: [String: Any],
        requestID: String,
        send: @escaping EventSender
    ) async throws -> [String: Any] {
        guard let ipa = payload["ipa_path"] as? String, !ipa.isEmpty else {
            throw CmdError.bad("ipa_path missing")
        }
        try requireExists(ipa)

        let ephemeralKey = try ephemeralKeyFile(payload: payload)
        defer { discardKey(ephemeralKey) }

        var creds: [String] = []
        if let keyID = payload["asc_api_key_id"] as? String, !keyID.isEmpty,
           let issuer = payload["asc_api_issuer_id"] as? String, !issuer.isEmpty,
           let key = ephemeralKey {
            // altool looks for the key by id in a set of well-known
            // directories unless given an explicit path.
            creds = [
                "--apiKey", keyID,
                "--apiIssuer", issuer,
                "--apiKeyPath", key,
            ]
        } else if let appleID = payload["apple_id"] as? String, !appleID.isEmpty,
                  let password = payload["app_specific_password"] as? String, !password.isEmpty {
            creds = ["-u", appleID, "-p", password]
        } else {
            return [
                "ok": false, "phase": "validate",
                "detail": "No Apple credentials were provided, so there is nothing to sign in with.",
            ]
        }

        let validate = try await streamProcess(
            executable: "/usr/bin/xcrun",
            argv: ["altool", "--validate-app", "-f", ipa, "-t", "ios"] + creds,
            phase: "validate",
            eventType: "asc.upload.line",
            requestID: requestID,
            send: send
        )
        guard validate.code == 0 else {
            return [
                "ok": false, "phase": "validate",
                "exit_code": Int(validate.code),
                "log_tail": validate.tail,
                "detail": "Apple rejected the build before upload.",
            ]
        }

        let upload = try await streamProcess(
            executable: "/usr/bin/xcrun",
            argv: ["altool", "--upload-app", "-f", ipa, "-t", "ios"] + creds,
            phase: "upload",
            eventType: "asc.upload.line",
            requestID: requestID,
            send: send
        )
        return [
            "ok": upload.code == 0,
            "phase": "upload",
            "exit_code": Int(upload.code),
            "log_tail": upload.tail,
            "detail": upload.code == 0
                ? "Uploaded. Apple is processing the build."
                : "The upload did not complete.",
        ]
    }

    /// Pull the generated app's source onto this Mac.
    ///
    /// Signing has to happen where Xcode is, and Xcode needs the actual
    /// files. Rather than making the user find, download and unzip a
    /// workspace by hand, the companion fetches it straight from the
    /// build server using the token the phone already holds.
    private func fetchWorkspace(
        payload: [String: Any],
        requestID: String,
        send: @escaping EventSender
    ) async throws -> [String: Any] {
        guard let urlString = payload["export_url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { throw CmdError.bad("export_url missing or not an http(s) URL") }
        guard let jobID = payload["job_id"] as? String, !jobID.isEmpty else {
            throw CmdError.bad("job_id missing")
        }
        // The job id names a directory, so it must not be able to climb
        // out of the workspaces folder.
        guard !jobID.contains("/"), !jobID.contains(".."), jobID.count <= 128 else {
            throw CmdError.bad("job_id is not a usable folder name")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        if let token = payload["token"] as? String, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        send([
            "v": 1, "kind": "event", "in_response_to": requestID,
            "type": "workspace.fetch.line",
            "payload": ["line": "Downloading your app's files…", "phase": "download"],
        ])

        let (tempFile, response) = try await URLSession.shared.download(for: request)
        // `download(for:)` hands us a file we own on every path, so it
        // has to be cleaned up on the failure branches too.
        defer { try? FileManager.default.removeItem(at: tempFile) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return [
                "ok": false,
                "detail": "The build server returned \(http.statusCode) for the workspace download.",
            ]
        }

        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/CodeGenie/workspaces", isDirectory: true)
        let dest = base.appendingPathComponent(jobID, isDirectory: true)
        // A previous attempt's files would otherwise shadow this one.
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        send([
            "v": 1, "kind": "event", "in_response_to": requestID,
            "type": "workspace.fetch.line",
            "payload": ["line": "Unpacking…", "phase": "unpack"],
        ])

        // `ditto` ships with macOS and handles the zip layout Finder
        // produces, which `unzip` sometimes mangles.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", tempFile.path, dest.path]
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            return ["ok": false, "detail": "Could not unpack the workspace zip."]
        }

        // The zip may contain a single top-level folder; the project
        // lives inside it, and that is what xcodebuild needs.
        let root = projectRoot(startingAt: dest.path)
        return ["ok": true, "workspace_root": root]
    }

    /// Find the folder that actually holds the Xcode project, in case
    /// the archive wrapped everything in one top-level directory.
    private func projectRoot(startingAt path: String) -> String {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        if entries.contains(where: { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }) {
            return path
        }
        let dirs = entries.filter { name in
            var isDir: ObjCBool = false
            let child = URL(fileURLWithPath: path).appendingPathComponent(name).path
            return fm.fileExists(atPath: child, isDirectory: &isDir) && isDir.boolValue
        }
        if dirs.count == 1 {
            return projectRoot(startingAt: URL(fileURLWithPath: path).appendingPathComponent(dirs[0]).path)
        }
        return path
    }

    /// Write an inline `.p8` to a private temporary file.
    ///
    /// The phone holds the signing key in its Keychain and hands it
    /// over the local connection for the length of one command. Keeping
    /// it in memory is not an option — `xcodebuild` and `altool` both
    /// take a *path* — so it goes to disk owner-only and is deleted by
    /// the caller's `defer`, whatever happens in between.
    ///
    /// Returns nil when the phone sent no inline key, in which case the
    /// caller falls back to `asc_api_key_path`.
    private func ephemeralKeyFile(payload: [String: Any]) throws -> String? {
        guard let pem = payload["asc_api_key_pem"] as? String,
              !pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codegenie-key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let path = dir.appendingPathComponent("asc-key.p8").path
        guard FileManager.default.createFile(
            atPath: path,
            contents: Data(pem.utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CmdError.bad("could not stage the signing key")
        }
        return path
    }

    /// Remove a staged key and its directory. Best-effort by design:
    /// a failure to clean up must not mask the command's real result,
    /// but it must still be attempted on every exit path.
    private func discardKey(_ path: String?) {
        guard let path else { return }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(at: dir)
    }

    /// ASC API key auth so Xcode can register devices and download
    /// profiles without an interactive 2FA prompt.
    private func authArgs(
        payload: [String: Any],
        root: String,
        keyOverride: String? = nil
    ) -> [String] {
        guard let keyID = payload["asc_api_key_id"] as? String, !keyID.isEmpty,
              let issuer = payload["asc_api_issuer_id"] as? String, !issuer.isEmpty
        else { return [] }

        let resolved: String
        if let keyOverride {
            resolved = keyOverride
        } else {
            guard let keyPath = payload["asc_api_key_path"] as? String, !keyPath.isEmpty
            else { return [] }
            resolved = keyPath.hasPrefix("/")
                ? keyPath
                : URL(fileURLWithPath: root).appendingPathComponent(keyPath).path
        }
        guard FileManager.default.fileExists(atPath: resolved) else { return [] }
        return [
            "-authenticationKeyID", keyID,
            "-authenticationKeyIssuerID", issuer,
            "-authenticationKeyPath", resolved,
        ]
    }

    private func writeExportOptions(path: String, method: String, teamID: String) throws {
        var dict: [String: Any] = [
            "method": method,
            "signingStyle": "automatic",
            "uploadSymbols": true,
            "destination": "export",
        ]
        if !teamID.isEmpty { dict["teamID"] = teamID }
        let data = try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func detectProject(in root: String) throws -> String {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        // A workspace wins when both exist — that is what Xcode opens.
        if let ws = entries.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return URL(fileURLWithPath: root).appendingPathComponent(ws).path
        }
        if let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return URL(fileURLWithPath: root).appendingPathComponent(proj).path
        }
        throw CmdError.bad("no .xcworkspace or .xcodeproj found in \(root)")
    }

    private func detectScheme(project: String) throws -> String {
        let flag = project.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        process.arguments = [flag, project, "-list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""

        // `xcodebuild -list` prints an indented list under "Schemes:".
        guard let range = text.range(of: "Schemes:") else {
            throw CmdError.bad("could not read schemes from \(project)")
        }
        let after = text[range.upperBound...]
        for raw in after.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return line }
        }
        throw CmdError.bad("no schemes defined in \(project)")
    }

    private func firstIPA(in directory: String) -> String? {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        guard let name = entries.first(where: { $0.hasSuffix(".ipa") }) else { return nil }
        return URL(fileURLWithPath: directory).appendingPathComponent(name).path
    }

    /// Runs xcodebuild, streaming each line as an event so the phone
    /// shows live progress. Archive builds routinely take minutes;
    /// silence for that long reads as a hang.
    private func streamXcodebuild(
        _ argv: [String],
        phase: String,
        requestID: String,
        send: @escaping EventSender
    ) async throws -> (code: Int32, tail: String) {
        try await streamProcess(
            executable: "/usr/bin/xcodebuild",
            argv: argv,
            phase: phase,
            eventType: "xcodebuild.line",
            requestID: requestID,
            send: send
        )
    }

    /// Run a long-lived tool, forwarding each line as an event.
    ///
    /// Shared by the archive and the TestFlight upload: both run for
    /// minutes, and both look like a hang if the phone sees nothing
    /// until they finish.
    private func streamProcess(
        executable: String,
        argv: [String],
        phase: String,
        eventType: String,
        requestID: String,
        send: @escaping EventSender
    ) async throws -> (code: Int32, tail: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = argv
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
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
                    guard let s = String(data: chunk, encoding: .utf8) else { continue }
                    for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
                        let line = String(raw)
                        send([
                            "v": 1, "kind": "event", "in_response_to": requestID,
                            "type": eventType,
                            "payload": ["line": line, "phase": phase],
                        ])
                        tail.append(line)
                        if tail.count > 300 { tail.removeFirst(tail.count - 300) }
                    }
                }
                continuation.resume()
            }
        }
        process.waitUntilExit()
        return (process.terminationStatus, tail.joined(separator: "\n"))
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
