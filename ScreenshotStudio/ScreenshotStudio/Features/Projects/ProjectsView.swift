import SwiftUI

/// The home surface: a gallery of saved screenshot sets with a prominent
/// "new set" action. Tapping a card opens the editor as a full-screen cover.
struct ProjectsView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var editing: ScreenshotProject?

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.projects.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.projects) { project in
                            Button {
                                Haptics.tap()
                                editing = project
                            } label: {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Motion.run(Motion.spring) { store.delete(project) }
                                    Haptics.warning()
                                } label: { Label("Delete set", systemImage: "trash") }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(LiquidGlassBackground().ignoresSafeArea())
        // The editor covers the floating tab bar for a focused, full-screen edit.
        .fullScreenCover(item: $editing) { project in
            StudioView(project: project)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot Studio")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .auroraStyle()
                Text("App Store screenshots, done right")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
            Spacer()
            Button {
                let project = store.create()
                Haptics.success()
                editing = project
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(LiquidGlass.auroraGradient, in: Circle())
                    .shadow(color: LiquidGlass.accent.opacity(0.5), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New screenshot set")
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            StudioMark(size: 92)
                .padding(.top, 40)
            Text("Create your first set")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Import iPhone screenshots and turn them into polished, store-ready images in a couple of taps.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            PrimaryButton(title: "New set", systemImage: "plus") {
                let project = store.create()
                Haptics.success()
                editing = project
            }
            .padding(.horizontal, 60)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }
}

private struct ProjectCard: View {
    let project: ScreenshotProject

    var body: some View {
        GlassSurface(tier: .flat, corner: 18) {
            VStack(alignment: .leading, spacing: 0) {
                ProjectThumbnail(project: project)
                    .frame(height: 200)
                    .padding(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label("\(project.slides.count)", systemImage: "photo")
                        Text("·")
                        Text(project.deviceSize.displayName)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), \(project.slides.count) screenshots, \(project.deviceSize.displayName)")
    }
}
