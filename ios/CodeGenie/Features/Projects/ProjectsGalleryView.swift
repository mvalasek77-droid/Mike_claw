import SwiftUI

struct ProjectsGalleryView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query: String = ""
    @State private var showDescribe = false
    /// Set when the user picks "Compare with…" from a row's context menu.
    @State private var compareOrigin: BuildJob?
    /// Set when the user picks "Revise this build…" — the TestFlight
    /// iteration loop: test on the phone, come back, describe changes.
    @State private var reviseOrigin: BuildJob?

    private var filtered: [BuildJob] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return session.recentJobs }
        return session.recentJobs.filter {
            $0.description.title.lowercased().contains(q)
                || $0.description.prompt.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    searchBar
                    if session.recentJobs.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { job in
                            Button {
                                session.openJob(job, backendID: session.backendJobIDs[job.id])
                            } label: {
                                ProjectCard(
                                    job: job,
                                    backendID: session.backendJobIDs[job.id],
                                    spend: session.backendJobIDs[job.id].flatMap { JobCostLog.shared.spend(for: $0) }
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(job.description.title)")
                            .accessibilityHint(session.backendJobIDs[job.id] != nil
                                ? "Attach to the live build"
                                : "Resume locally")
                            .contextMenu {
                                if session.backendJobIDs[job.id] != nil {
                                    Button {
                                        reviseOrigin = job
                                        Haptics.selection()
                                    } label: {
                                        Label("Revise this build…", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    Button {
                                        session.openAppStoreConnect(for: job)
                                        Haptics.selection()
                                    } label: {
                                        Label("Submit to the App Store", systemImage: "paperplane.fill")
                                    }
                                    Button {
                                        compareOrigin = job
                                        Haptics.selection()
                                    } label: {
                                        Label("Compare with…", systemImage: "rectangle.split.2x1")
                                    }
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showDescribe) {
            DescribeAppView { description in
                showDescribe = false
                _ = session.startBuild(from: description)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $reviseOrigin) { job in
            if let backend = session.backendJobIDs[job.id] {
                ReviseBuildSheet(job: job, backendID: backend)
                    .environmentObject(session)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
        .sheet(item: $compareOrigin) { job in
            if let backend = session.backendJobIDs[job.id] {
                CompareJobsPickerView(originJob: job, originBackendID: backend)
                    .environmentObject(session)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("My Apps")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Spacer()
            Button { showDescribe = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .frame(width: 38, height: 38)
                    .background(LiquidGlass.auroraGradient, in: Circle())
            }
            .accessibilityLabel("New build")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            TextField("Search your apps", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(LiquidGlass.primaryText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private var emptyState: some View {
        GlassSurface(tier: .raised) {
            VStack(spacing: 16) {
                CodeGenieLogo(size: 80, animate: true)
                Text("No apps yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Describe an idea and CodeGenie will scaffold a real Xcode project for you.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                PrimaryButton(title: "Start your first build", systemImage: "wand.and.stars", style: .filled) {
                    showDescribe = true
                }
                .frame(maxWidth: 240)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProjectCard: View {
    let job: BuildJob
    var backendID: String? = nil
    var spend: JobCostLog.Spend? = nil

    var body: some View {
        GlassSurface(tier: .raised, corner: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: job.description.category.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(LiquidGlass.accent)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.description.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(job.description.category.label)
                            .font(.caption2)
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                    Spacer()
                    Text(job.stage.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                }
                Text(job.description.prompt)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let backendID {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .bold))
                                .accessibilityHidden(true)
                            Text("forked · \(backendID.prefix(12))")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(LiquidGlass.accentSecondary.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(LiquidGlass.accentSecondary.opacity(0.35)))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                        .accessibilityLabel("Forked from build \(backendID)")
                    }
                    if let spend, spend.usd > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .accessibilityHidden(true)
                            Text(String(format: "$%.3f spent", spend.usd))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(LiquidGlass.success.opacity(0.18), in: Capsule())
                        .overlay(Capsule().strokeBorder(LiquidGlass.success.opacity(0.35)))
                        .foregroundStyle(LiquidGlass.success)
                        .accessibilityLabel(String(format: "Spent %.3f dollars on this build", spend.usd))
                    }
                }
            }
            .padding(16)
        }
    }
}


/// "I tested it on my phone — now change X." Collects a revision brief
/// against a finished build and spawns the seeded follow-up job. The
/// original build is never modified, so Compare can diff the two.
private struct ReviseBuildSheet: View {
    let job: BuildJob
    let backendID: String
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    private let client = SwarmClient()

    @State private var prompt: String = ""
    @State private var reupload: Bool = Credentials.shared.hasAppleDevCreds
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Revise \(job.description.title)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Tested it in TestFlight? Describe what to change. CodeGenie revises the existing app — same project, new build number — and can re-upload automatically when it's green.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    GlassCard(title: "What should change?", icon: "pencil.and.outline", tint: LiquidGlass.accent) {
                        TextEditor(text: $prompt)
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .accessibilityLabel("Revision request")
                        Text("Example: “The streak counter resets at midnight UTC — make it reset at local midnight. Also make the Add button bigger.”")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    }

                    GlassCard(title: "After the revision", icon: "icloud.and.arrow.up", tint: LiquidGlass.accentSecondary) {
                        Toggle(isOn: $reupload) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Re-upload to TestFlight when green")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                Text(Credentials.shared.hasAppleDevCreds
                                     ? "Uses your saved Apple credentials. Testers get the new build automatically."
                                     : "Add Apple credentials in Settings to enable automatic re-upload.")
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                            }
                        }
                        .tint(LiquidGlass.accent)
                        .disabled(!Credentials.shared.hasAppleDevCreds)
                    }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.warning)
                            .accessibilityLabel("Error: \(errorText)")
                    }

                    PrimaryButton(
                        title: submitting ? "Starting revision…" : "Start revision",
                        systemImage: "arrow.triangle.2.circlepath",
                        style: .filled
                    ) { startRevision() }
                    .disabled(submitting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Color.clear.frame(height: 20)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func startRevision() {
        let brief = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty, !submitting else { return }
        submitting = true
        errorText = nil
        let ship = reupload
            ? ShipConfig.fromCredentials(bundleID: defaultBundleID(for: job.description.title))
            : nil
        Task {
            do {
                let newID = try await client.revise(jobID: backendID, prompt: brief, ship: ship)
                await MainActor.run {
                    session.adoptForkedJob(originalDescription: job.description,
                                           newID: newID, titleSuffix: "(rev)")
                    Haptics.success()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    errorText = "Couldn't start the revision: \(error.localizedDescription)"
                    Haptics.error()
                }
            }
        }
    }

    private func defaultBundleID(for title: String) -> String {
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return "com.codegenie.\(slug.isEmpty ? "app" : slug)"
    }
}
