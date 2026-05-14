import SwiftUI

struct ProjectsGalleryView: View {
    @EnvironmentObject private var session: AppSession
    @State private var query: String = ""
    @State private var showDescribe = false

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
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("My Apps")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button { showDescribe = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(LiquidGlass.auroraGradient, in: Circle())
            }
            .accessibilityLabel("New build")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Search your apps", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
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
                    .foregroundStyle(.white)
                Text("Describe an idea and CodeGenie will scaffold a real Xcode project for you.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
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
                            .foregroundStyle(.white)
                        Text(job.description.category.label)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text(job.stage.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(job.description.prompt)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
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
