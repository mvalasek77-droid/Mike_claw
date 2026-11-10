import SwiftUI

/// What the build actually produced.
///
/// An iPhone cannot run another app's unsigned code, so there is no
/// honest way to "preview" the result here. What this can do is show
/// the real thing that was made — every file, readable — and point at
/// the two real ways to see it running: TestFlight, or Xcode on a Mac.
struct BuiltAppView: View {
    let job: BuildJob

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @StateObject private var swarm = SwarmClient()
    @StateObject private var companion = CompanionBridge.shared

    @State private var load: LoadState = .loading
    @State private var openFile: OpenFile?
    @State private var macStatus: String?
    @State private var macBusy = false
    @State private var exportedCopy: URL?
    @State private var exporting = false

    enum LoadState: Equatable {
        case loading
        case loaded([String])
        case failed(String)
        /// The build never reached a server, so there is nothing to list.
        case unavailable
    }

    struct OpenFile: Identifiable {
        let path: String
        var id: String { path }
    }

    private var backendID: String? { session.backendJobIDs[job.id] }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        explainerCard
                        filesSection
                        actions
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(job.description.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadFiles() }
        .sheet(item: $openFile) { file in
            SourceFileView(path: file.path, jobID: backendID ?? "", swarm: swarm)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: Sections

    private var explainerCard: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("This is your app")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Below is the real project CodeGenie wrote — the same files Xcode builds from. To see it running, install it on your iPhone through TestFlight or open it in Xcode on your Mac.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var filesSection: some View {
        switch load {
        case .loading:
            GlassSurface(tier: .flat, corner: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(LiquidGlass.accent)
                    Text("Fetching the file list…")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    Spacer(minLength: 0)
                }
                .padding(16)
            }

        case .failed(let reason):
            messageCard(
                icon: "wifi.exclamationmark",
                title: "Couldn't load the files",
                detail: reason,
                retry: true
            )

        case .unavailable:
            messageCard(
                icon: "tray",
                title: "No files to show",
                detail: "This build isn't linked to a finished project on the server. Start it again from Home and its files will appear here.",
                retry: false
            )

        case .loaded(let files):
            if files.isEmpty {
                messageCard(
                    icon: "tray",
                    title: "The project is empty",
                    detail: "The build finished without writing any files. That shouldn't happen — open the build and check its transcript.",
                    retry: true
                )
            } else {
                fileList(files)
            }
        }
    }

    private func fileList(_ files: [String]) -> some View {
        let ordered = Self.ordered(files)
        let swiftCount = files.filter { $0.hasSuffix(".swift") }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(files.count) file\(files.count == 1 ? "" : "s") · \(swiftCount) Swift")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                .accessibilityAddTraits(.isHeader)
            ForEach(ordered, id: \.self) { path in
                Button {
                    Haptics.selection()
                    openFile = OpenFile(path: path)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: Self.icon(for: path))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(LiquidGlass.accent.opacity(0.16)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            let folder = (path as NSString).deletingLastPathComponent
                            if !folder.isEmpty {
                                Text(folder)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.35))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\((path as NSString).lastPathComponent), in \((path as NSString).deletingLastPathComponent)")
                .accessibilityHint("Shows this file's contents")
            }
        }
    }

    private func messageCard(icon: String, title: String, detail: String, retry: Bool) -> some View {
        GlassSurface(tier: .flat, corner: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if retry {
                    PrimaryButton(title: "Try again", systemImage: "arrow.clockwise", style: .glass) {
                        Task { await loadFiles() }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Put it on my iPhone", systemImage: "iphone.gen3", style: .filled) {
                dismiss()
                session.openAppStoreConnect(for: job)
            }
            .accessibilityHint("Opens the step-by-step guide to installing through TestFlight")

            if companion.isConnected, backendID != nil {
                PrimaryButton(
                    title: macBusy ? "Sending to your Mac…" : "Open in Xcode on my Mac",
                    systemImage: "macbook",
                    style: .glass
                ) {
                    Task { await openOnMac() }
                }
                .disabled(macBusy)
            }

            if backendID != nil {
                if let exportedCopy {
                    ShareLink(item: exportedCopy) {
                        Label("Share the project (.zip)", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                } else {
                    Button {
                        Task { await exportCopy() }
                    } label: {
                        Label(exporting ? "Preparing a copy…" : "Save a copy of the code", systemImage: "arrow.down.doc")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(exporting)
                }
            }

            if let macStatus {
                Text(macStatus)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Work

    private func loadFiles() async {
        guard let backendID else {
            load = .unavailable
            return
        }
        load = .loading
        do {
            load = .loaded(try await swarm.files(jobID: backendID))
        } catch {
            load = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func openOnMac() async {
        guard let backendID, let exportURL = swarm.exportURL(jobID: backendID) else { return }
        macBusy = true
        defer { macBusy = false }
        do {
            macStatus = "Copying the project to your Mac…"
            let root = try await companion.fetchWorkspace(
                jobID: backendID,
                exportURL: exportURL.absoluteString,
                token: Credentials.shared.backendToken
            )
            try await companion.openXcodeProject(root)
            macStatus = "Open in Xcode on your Mac. Press ⌘R there to run it."
            Haptics.success()
        } catch {
            macStatus = "Couldn't reach your Mac. Check it's awake and the companion is running."
            Haptics.error()
        }
    }

    private func exportCopy() async {
        guard let backendID else { return }
        exporting = true
        defer { exporting = false }
        do {
            exportedCopy = try await swarm.downloadExport(jobID: backendID)
            Haptics.success()
        } catch {
            macStatus = "Couldn't download the project. Try again in a moment."
            Haptics.error()
        }
    }

    // MARK: Presentation helpers

    /// Source first, then everything else, each alphabetical — the
    /// code is what people open this screen to read.
    static func ordered(_ files: [String]) -> [String] {
        files.sorted { a, b in
            let aSwift = a.hasSuffix(".swift"), bSwift = b.hasSuffix(".swift")
            if aSwift != bSwift { return aSwift }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func icon(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "json", "plist", "xcprivacy", "yml", "yaml": "curlybraces"
        case "md", "txt": "doc.text"
        case "png", "jpg", "jpeg", "pdf", "svg": "photo"
        case "pbxproj", "xcconfig", "entitlements": "gearshape"
        default: "doc"
        }
    }
}

// MARK: - One file

private struct SourceFileView: View {
    let path: String
    let jobID: String
    @ObservedObject var swarm: SwarmClient

    @Environment(\.dismiss) private var dismiss
    @State private var contents: String?
    @State private var failure: String?

    /// Enough to read any source file; a guard against laying out a
    /// multi-megabyte generated asset as one text view.
    private static let displayLimit = 200_000

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                if let contents {
                    ScrollView([.vertical, .horizontal]) {
                        Text(contents.isEmpty ? "(empty file)" : String(contents.prefix(Self.displayLimit)))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.92))
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let failure {
                    VStack(spacing: 12) {
                        Text("Couldn't open this file")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(failure)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .multilineTextAlignment(.center)
                        PrimaryButton(title: "Try again", systemImage: "arrow.clockwise", style: .glass) {
                            Task { await fetch() }
                        }
                        .frame(maxWidth: 220)
                    }
                    .padding(24)
                } else {
                    ProgressView().tint(LiquidGlass.accent)
                }
            }
            .navigationTitle((path as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await fetch() }
    }

    private func fetch() async {
        failure = nil
        do {
            contents = try await swarm.file(jobID: jobID, path: path)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
