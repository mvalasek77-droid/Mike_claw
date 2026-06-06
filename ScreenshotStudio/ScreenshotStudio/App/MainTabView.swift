import SwiftUI

struct MainTabView: View {
    @State private var tab: Tab = .studio

    enum Tab: Hashable { case studio, projects, guide, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .studio, .projects: ProjectsView()
                case .guide:    ASCGuideView()
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
                tab(.projects, icon: "square.grid.2x2.fill", label: "Sets")
                tab(.guide,    icon: "checklist",            label: "Guide")
                tab(.settings, icon: "gearshape.fill",       label: "Settings")
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
            .foregroundStyle(isSelected(t) ? .white : LiquidGlass.primaryText.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                Group {
                    if isSelected(t) {
                        Capsule().fill(LiquidGlass.auroraGradient.opacity(0.85))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected(t) ? .isSelected : [])
    }

    // "Sets" and the studio share the projects surface; treat both as selected.
    private func isSelected(_ t: MainTabView.Tab) -> Bool {
        if t == .projects { return selected == .projects || selected == .studio }
        return selected == t
    }
}
