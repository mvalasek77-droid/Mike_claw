import SwiftUI

/// Phase 3: Perfection Mode — 9-axis quality grid with scores,
/// auto-fix, and re-check. Shown after the user confirms the preview.
///
/// The axes mirror the backend's `PerfectionRun.axes` but are
/// displayed with human-friendly names and colour-coded dots.
struct PerfectionScorecardView: View {
    let job: BuildJob
    @ObservedObject var pipeline: PipelineClient
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var perfectionRun: PerfectionRun?
    @State private var isRunning: Bool = false
    @State private var error: String?
    @State private var navigateToMetadata: Bool = false
    @State private var navigateToShip: Bool = false

    /// The 9 axes we display, keyed to match the backend's `PerfectionAxis.key`.
    private struct AxisDisplay: Identifiable {
        let key: String
        let name: String
        let icon: String
        var id: String { key }
    }

    private static let axes: [AxisDisplay] = [
        AxisDisplay(key: "apple_review",       name: "Apple Review",       icon: "app.badge.fill"),
        AxisDisplay(key: "accessibility",       name: "Accessibility",      icon: "figure.roll"),
        AxisDisplay(key: "performance",        name: "Performance",         icon: "gauge.with.dots.needle.33percent"),
        AxisDisplay(key: "security",            name: "Security",            icon: "lock.shield.fill"),
        AxisDisplay(key: "grammar",             name: "Grammar",             icon: "textformat.abc"),
        AxisDisplay(key: "ui_polish",           name: "UI Polish",           icon: "paintbrush.fill"),
        AxisDisplay(key: "device_compat",       name: "Device Compat",       icon: "ipad.and.iphone"),
        AxisDisplay(key: "architecture",        name: "Architecture",        icon: "layer.group"),
        AxisDisplay(key: "packaging",           name: "Packaging",           icon: "shippingbox.fill"),
    ]

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    summaryRing
                    axisGrid
                    if let run = perfectionRun {
                        findingsSection(run)
                    }
                    if let err = error {
                        errorBanner(err)
                    }
                    actionsSection
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .navigationDestination(isPresented: $navigateToMetadata) {
            MetadataReviewView(job: job, pipeline: pipeline)
        }
        .navigationDestination(isPresented: $navigateToShip) {
            ShipConfirmView(job: job, pipeline: pipeline)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Perfection Mode")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("10,000 probes across 9 quality axes")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            Spacer()
        }
    }

    // MARK: - Summary ring

    private var summaryRing: some View {
        GlassSurface(tier: .deep) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 10)
                        .frame(width: 120, height: 120)
                    Circle()
                        .trim(from: 0, to: overallScore / 100)
                        .stroke(
                            LinearGradient(
                                colors: [LiquidGlass.accent, LiquidGlass.accentSecondary, LiquidGlass.success],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(Motion.spring, value: overallScore)
                    VStack(spacing: 2) {
                        Text("\(overallScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .contentTransition(.numericText())
                        Text("/ 100")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                }
                Text(gateLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(gateColor)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var overallScore: Double {
        guard let run = perfectionRun else { return 0 }
        return run.score
    }

    private var gateLabel: String {
        perfectionRun?.gateLabel ?? "Not yet run"
    }

    private var gateColor: Color {
        guard let run = perfectionRun else { return LiquidGlass.primaryText.opacity(0.4) }
        return run.isReady ? LiquidGlass.success : LiquidGlass.warning
    }

    // MARK: - Axis grid

    private var axisGrid: some View {
        GlassCard(title: "Quality Axes", icon: "chart.bar.doc.horizontal.fill", tint: LiquidGlass.accent) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(Self.axes) { axis in
                    axisCell(axis)
                }
            }
        }
    }

    private func axisCell(_ axis: AxisDisplay) -> some View {
        let score = scoreForAxis(axis.key)
        let dotColor = colorForScore(score)

        return GlassSurface(tier: .flat, corner: 14) {
            HStack(spacing: 8) {
                Image(systemName: axis.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dotColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(dotColor.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(axis.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(score)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
    }

    private func scoreForAxis(_ key: String) -> Int {
        guard let run = perfectionRun else { return 0 }
        // Map axis key to PerfectionAxis score
        guard let match = run.axes.first(where: { $0.key == key }) else {
            // Try a fuzzy match on title
            return run.axes.first(where: { $0.title.lowercased().contains(key.replacingOccurrences(of: "_", with: " ")) })
                .map { Int(Double($0.passed) / Double(max($0.probes, 1)) * 100) } ?? 0
        }
        return Int(Double(match.passed) / Double(max(match.probes, 1)) * 100)
    }

    private func colorForScore(_ score: Int) -> Color {
        if score >= 80 { return LiquidGlass.success }
        if score >= 50 { return LiquidGlass.warning }
        return .red
    }

    // MARK: - Findings

    private func findingsSection(_ run: PerfectionRun) -> some View {
        GlassCard(title: "Findings", icon: "magnifyingglass", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(run.findings.prefix(5)) { finding in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.severity == "blocker" ? "xmark.circle.fill" : (finding.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(finding.severity == "blocker" ? .red : (finding.severity == "warning" ? LiquidGlass.warning : LiquidGlass.accent))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            if let rec = finding.recommendation {
                                Text(rec)
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red.opacity(0.9))
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if isRunning {
                PrimaryButton(title: "Running Perfection Mode…", systemImage: "checkmark.shield.fill", style: .filled) { }
                    .disabled(true)
            } else if perfectionRun == nil {
                PrimaryButton(title: "Run Perfection Mode", systemImage: "checkmark.shield.fill", style: .filled) {
                    Task { await runPerfection() }
                }
            }

            if let run = perfectionRun {
                let blockerCount = run.findings.filter { $0.severity == "blocker" }.count
                let warningCount = run.findings.filter { $0.severity == "warning" }.count
                if blockerCount > 0 || warningCount > 0 {
                    PrimaryButton(
                        title: "Auto-fix \(blockerCount + warningCount) issues",
                        systemImage: "wrench.and.screwdriver.fill",
                        style: .glass
                    ) {
                        Task { await runPerfection() }
                    }
                }

                PrimaryButton(title: "Re-check in simulator", systemImage: "arrow.triangle.2.circlepath", style: .glass) {
                    Task { await runPerfection() }
                }

                PrimaryButton(title: "Continue to metadata →", systemImage: "doc.text.fill", style: .filled) {
                    Haptics.success()
                    navigateToMetadata = true
                }

                PrimaryButton(title: "Skip to Ship", systemImage: "paperplane.fill", style: .ghost) {
                    Haptics.selection()
                    navigateToShip = true
                }
            }
        }
    }

    // MARK: - Logic

    private func runPerfection() async {
        isRunning = true
        error = nil
        defer { isRunning = false }
        do {
            let jobID = session.currentJobBackendID ?? ""
            let swarm = SwarmClient()
            let run = try await swarm.runPerfection(jobID: jobID)
            withAnimation(Motion.spring) {
                perfectionRun = run
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}