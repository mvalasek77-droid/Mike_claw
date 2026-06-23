import SwiftUI
import UIKit

/// Confirms the export plan, runs the render, and reports the result. The
/// progress meter is driven by real per-image completion from
/// `ExportCoordinator`, so it never lies about what's happening.
struct ExportSheet: View {
    let project: ScreenshotProject

    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = ExportCoordinator()
    @State private var shareURLs: [URL]?
    @State private var isPreparingShare = false
    @State private var allLanguages = false

    private var sizes: [ASCDeviceSize] { project.exportSizes }
    private var languages: [String] {
        (project.languages.count > 1 && allLanguages) ? project.languages : [project.activeLanguage]
    }
    private var totalImages: Int { sizes.count * languages.count * project.slides.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                switch coordinator.phase {
                case .finished(let count):
                    successCard(count: count)
                case .failed(let message):
                    errorCard(message: message)
                default:
                    planCard
                    if project.languages.count > 1 { languageCard }
                    if coordinator.isRunning { progressCard }
                }

                actionButtons
            }
            .padding(20)
        }
        .background(LiquidGlassBackground().ignoresSafeArea())
        .sheet(item: Binding(
            get: { shareURLs.map { ShareBox(urls: $0) } },
            set: { shareURLs = $0?.urls }
        )) { box in
            ShareSheet(items: box.urls)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up.on.square.fill")
                .font(.system(size: 34))
                .foregroundStyle(LiquidGlass.auroraGradient)
            Text("Export screenshots")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
        }
        .padding(.top, 8)
    }

    private var planCard: some View {
        GlassCard(title: "What gets rendered", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sizes) { size in
                    HStack {
                        Image(systemName: size.family.symbol)
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(size.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(size.resolutionLabel(for: project.orientation))
                                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        }
                        Spacer()
                        Text("\(project.slides.count)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            + Text(" image\(project.slides.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                    }
                }
                Divider().overlay(.white.opacity(0.1))
                HStack {
                    Text("Total")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                    Text("\(totalImages) PNGs")
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(LiquidGlass.accent)
                }
            }
        }
    }

    private var languageCard: some View {
        GlassCard(title: "Languages", icon: "globe") {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(label: "Export all \(project.languages.count) languages",
                          systemImage: "character.bubble", isOn: $allLanguages)
                Text(allLanguages
                     ? "Renders every language's caption set — \(project.languages.map(ASCLanguage.displayName(for:)).joined(separator: ", "))."
                     : "Renders only \(ASCLanguage.displayName(for: project.activeLanguage)).")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                ProgressView(value: coordinator.progress)
                    .tint(LiquidGlass.accent)
                Text(coordinator.phase == .saving ? "Saving to Photos…" : "Rendering at full resolution…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
        }
    }

    private func successCard(count: Int) -> some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LiquidGlass.success)
                    .symbolEffect(.bounce, value: count)
                Text("\(count) screenshot\(count == 1 ? "" : "s") saved")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Find them in the “Screenshot Studio” album in Photos, ready to upload to App Store Connect.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func errorCard(message: String) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidGlass.warning)
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch coordinator.phase {
        case .finished:
            PrimaryButton(title: "Done", systemImage: "checkmark") { dismiss() }
        case .failed:
            VStack(spacing: 10) {
                if coordinator.needsPhotoAccess {
                    PrimaryButton(title: "Open Settings", systemImage: "gearshape.fill") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                PrimaryButton(title: "Try again", systemImage: "arrow.clockwise",
                              style: coordinator.needsPhotoAccess ? .glass : .filled) {
                    Task { await coordinator.export(project: project, sizes: sizes, languages: languages) }
                }
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
        default:
            VStack(spacing: 10) {
                PrimaryButton(title: "Save to Photos", systemImage: "photo.badge.checkmark",
                              isEnabled: !coordinator.isRunning && totalImages > 0) {
                    Task { await coordinator.export(project: project, sizes: sizes, languages: languages) }
                }
                PrimaryButton(title: isPreparingShare ? "Preparing…" : "Share PNGs",
                              systemImage: "square.and.arrow.up", style: .glass,
                              isEnabled: !coordinator.isRunning && !isPreparingShare && totalImages > 0) {
                    isPreparingShare = true
                    Task {
                        let urls = await ScreenshotRenderer.renderShareFilesAsync(of: project, sizes: sizes, languages: languages)
                        isPreparingShare = false
                        shareURLs = urls
                    }
                }
            }
        }
    }
}

/// Identifiable wrapper so a `[URL]` can drive `.sheet(item:)`.
private struct ShareBox: Identifiable {
    let id = UUID()
    let urls: [URL]
}
