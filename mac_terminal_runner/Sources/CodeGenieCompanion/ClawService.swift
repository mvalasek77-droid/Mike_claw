import Foundation

/// Manages the Claw Code binary lifecycle: auto-install, start/stop server,
/// and HTTP forwarding to the Claw REST API running on localhost.
final class ClawService {
    static let shared = ClawService()

    private let clawBinaryPath: URL
    private let downloadURL = "https://github.com/mvalasek77-droid/Mike_claw/releases/latest/download/claw-macos-aarch64"
    private let port: UInt16 = 8765
    private let baseURL = "http://localhost:8765"

    /// Reference to the running `claw serve` process so we can terminate it later.
    private var serverProcess: Process?
    private let lock = NSLock()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".codegenie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.clawBinaryPath = dir.appendingPathComponent("claw")
    }

    // MARK: - Binary Installation

    /// Returns true if the claw binary exists at the expected path.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: clawBinaryPath.path)
    }

    /// Downloads the claw binary if it doesn't already exist.
    /// Thread-safe — multiple callers won't race.
    func ensureInstalled() async throws {
        if isInstalled {
            NSLog("[ClawService] Claw binary already installed at \(clawBinaryPath.path)")
            return
        }
        NSLog("[ClawService] Claw binary not found, downloading from \(downloadURL)...")
        guard let url = URL(string: downloadURL) else {
            throw ClawError.bad("Invalid download URL")
        }

        let (tmpURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClawError.bad("Download failed with HTTP \(statusCode)")
        }

        // Move to final location
        let dir = clawBinaryPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Remove any previous temp file at destination
        try? FileManager.default.removeItem(at: clawBinaryPath)
        try FileManager.default.moveItem(at: tmpURL, to: clawBinaryPath)

        // Make executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: clawBinaryPath.path
        )
        NSLog("[ClawService] Claw binary installed at \(clawBinaryPath.path)")
    }

    // MARK: - Server Lifecycle

    /// Starts the claw server if it's not already running.
    /// First ensures the binary is installed, then checks health,
    /// and only starts if health check fails.
    func ensureServerRunning() async throws {
        try await ensureInstalled()

        if await isHealthy() {
            NSLog("[ClawService] Claw server already running on port \(port)")
            return
        }

        NSLog("[ClawService] Starting claw serve \(port)...")
        try startServer()
        // Give it a moment to bind
        try await Task.sleep(for: .milliseconds(500))
        // Poll health for up to 10 seconds
        for i in 1...20 {
            if await isHealthy() {
                NSLog("[ClawService] Claw server is healthy (attempt \(i))")
                return
            }
            NSLog("[ClawService] Waiting for claw server... attempt \(i)")
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ClawError.bad("Claw server failed to start / health check timed out")
    }

    /// Checks if the Claw server is reachable at /api/health.
    func isHealthy() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/health") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (200...299).contains(statusCode)
        } catch {
            return false
        }
    }

    /// Starts `claw serve <port>` as a background Process.
    private func startServer() throws {
        lock.lock()
        defer { lock.unlock() }

        // Don't start a second process
        if serverProcess != nil && serverProcess!.isRunning { return }

        let process = Process()
        process.executableURL = clawBinaryPath
        process.arguments = ["serve", "\(port)"]

        // Redirect stdout/stderr to a log file so we can diagnose issues
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codegenie", isDirectory: true)
        let logPath = logDir.appendingPathComponent("claw-server.log")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if let logFile = FileHandle(forWritingAtPath: logPath.path) ?? FileHandle(forUpdatingAtPath: logPath.path) {
            process.standardOutput = logFile
            process.standardError = logFile
        }

        try process.run()
        self.serverProcess = process
        NSLog("[ClawService] Claw server process started (PID: \(process.processIdentifier))")
    }

    /// Stops the claw server process if running.
    func stopServer() {
        lock.lock()
        defer { lock.unlock() }
        if let process = serverProcess, process.isRunning {
            process.terminate()
            NSLog("[ClawService] Claw server process terminated")
        }
        serverProcess = nil
    }

    // MARK: - HTTP Forwarding

    /// POST to /api/build — creates a new build job.
    func startBuild(payload: [String: Any]) async throws -> [String: Any] {
        try await ensureServerRunning()
        let url = URL(string: "\(baseURL)/api/build")!
        return try await postJSON(url: url, body: payload)
    }

    /// GET /api/build/{job_id}/status — polls build status.
    func buildStatus(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/status") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await getJSON(url: url)
    }

    /// POST /api/build/{job_id}/github — push build output to GitHub.
    func pushToGithub(jobID: String, payload: [String: Any]) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/github") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await postJSON(url: url, body: payload)
    }

    // MARK: - Pipeline endpoints (Build → Ship)

    /// POST /api/build/{job_id}/patch — incremental bug fix.
    func patchBuild(jobID: String, bugDescription: String, filesToEdit: [String]? = nil) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/patch") else {
            throw ClawError.bad("Invalid job ID")
        }
        var body: [String: Any] = ["bug_description": bugDescription]
        if let files = filesToEdit { body["files_to_edit"] = files }
        return try await postJSON(url: url, body: body)
    }

    /// POST /api/build/{job_id}/icon — generate/regenerate app icon.
    func generateIcon(jobID: String, prompt: String? = nil) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/icon") else {
            throw ClawError.bad("Invalid job ID")
        }
        var body: [String: Any] = [:]
        if let p = prompt { body["prompt"] = p }
        return try await postJSON(url: url, body: body)
    }

    /// GET /api/build/{job_id}/perfection — run 9-axis quality audit.
    func runPerfection(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/perfection") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await getJSON(url: url)
    }

    /// POST /api/build/{job_id}/asc-metadata — generate App Store Connect metadata.
    func generateMetadata(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/asc-metadata") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await postJSON(url: url, body: [:])
    }

    /// POST /api/build/{job_id}/screenshots — trigger screenshot automation.
    func takeScreenshots(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/screenshots") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await postJSON(url: url, body: [:])
    }

    /// POST /api/build/{job_id}/upload — archive and upload to App Store Connect.
    func uploadBuild(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/upload") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await postJSON(url: url, body: [:])
    }

    /// POST /api/build/{job_id}/submit — submit for App Store review.
    func submitForReview(jobID: String) async throws -> [String: Any] {
        try await ensureServerRunning()
        guard let url = URL(string: "\(baseURL)/api/build/\(jobID)/submit") else {
            throw ClawError.bad("Invalid job ID")
        }
        return try await postJSON(url: url, body: [:])
    }

    // MARK: - URLSession helpers

    private func postJSON(url: URL, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // builds can take a while

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawError.bad("Non-HTTP response from Claw server")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ClawError.bad("Claw server returned HTTP \(httpResponse.statusCode): \(bodyText)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClawError.bad("Invalid JSON response from Claw server")
        }
        return json
    }

    private func getJSON(url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClawError.bad("Non-HTTP response from Claw server")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ClawError.bad("Claw server returned HTTP \(httpResponse.statusCode): \(bodyText)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClawError.bad("Invalid JSON response from Claw server")
        }
        return json
    }
}

enum ClawError: Error, CustomStringConvertible {
    case bad(String)
    var description: String {
        switch self { case .bad(let s): return s }
    }
}