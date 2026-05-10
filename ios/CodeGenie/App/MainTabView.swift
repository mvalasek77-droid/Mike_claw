import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @State private var tab: Tab = .home

    enum Tab: Hashable { case home, build, play, apps, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:     HomeView()
                case .build:    BuildPlaceholderView { tab = .home }
                case .play:     GameHomeView()
                case .apps:     ProjectsGalleryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selected: $tab)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard)
    }
}

private struct TabBar: View {
    @Binding var selected: MainTabView.Tab
    var body: some View {
        GlassSurface(tier: .deep, corner: 28) {
            HStack(spacing: 2) {
                tab(.home,     icon: "house.fill",            label: "Home")
                tab(.build,    icon: "wand.and.stars",        label: "Build")
                tab(.play,     icon: "gamecontroller.fill",   label: "Play")
                tab(.apps,     icon: "square.grid.2x2.fill",  label: "Apps")
                tab(.settings, icon: "gearshape.fill",        label: "Settings")
            }
            .padding(8)
        }
        .frame(maxWidth: 460)
    }

    private func tab(_ t: MainTabView.Tab, icon: String, label: String) -> some View {
        Button {
            Motion.run(Motion.snap) { selected = t }
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected == t ? .white : .white.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                Group {
                    if selected == t {
                        Capsule().fill(LiquidGlass.auroraGradient.opacity(0.85))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected == t ? .isSelected : [])
    }
}

/// Build tab is a "kick off" landing — opens the Describe sheet directly.
private struct BuildPlaceholderView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showDescribe = true
    var onClose: () -> Void

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                CodeGenieMark()
                    .padding(.top, 80)
                Spacer()
            }
        }
        .sheet(isPresented: $showDescribe, onDismiss: { onClose() }) {
            DescribeAppView { description in
                showDescribe = false
                _ = session.startBuild(from: description)
                onClose()
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }
}
