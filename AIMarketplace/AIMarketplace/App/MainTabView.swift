import SwiftUI

struct MainTabView: View {
    @State private var tab: Tab = Tab.initial

    enum Tab: Hashable {
        case home, charts, publish, library, profile

        /// DEBUG screenshot helper: `-tab charts|publish|library|profile`.
        static var initial: Tab {
            #if DEBUG
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-tab"), i + 1 < a.count {
                switch a[i + 1] {
                case "charts": return .charts
                case "publish": return .publish
                case "library": return .library
                case "profile": return .profile
                default: break
                }
            }
            #endif
            return .home
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:    BrowseHomeView()
                case .charts:  ChartsView()
                case .publish: PublishHomeView()
                case .library: LibraryView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selected: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard)
    }
}

private struct TabBar: View {
    @Binding var selected: MainTabView.Tab
    @Namespace private var pill

    var body: some View {
        bar
            .shadow(color: .black.opacity(0.38), radius: 22, x: 0, y: 12)
            .frame(maxWidth: 480)
    }

    private var tabRow: some View {
        HStack(spacing: 2) {
            tab(.home,    icon: "house.fill",            label: "Home")
            tab(.charts,  icon: "chart.bar.fill",        label: "Top 10")
            tab(.publish, icon: "plus.circle.fill",      label: "Publish")
            tab(.library, icon: "rectangle.stack.fill",  label: "Library")
            tab(.profile, icon: "person.fill",           label: "You")
        }
        .padding(6)
    }

    /// Native iOS 26 Liquid Glass via GlassEffectContainer (composites correctly
    /// over scrolling/tinted content); frosted-material fallback below iOS 26.
    @ViewBuilder private var bar: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                tabRow.glassEffect(.regular, in: .capsule)
            }
        } else { materialBar }
        #else
        materialBar
        #endif
    }

    private var materialBar: some View {
        tabRow
            .background { Capsule(style: .continuous).fill(.ultraThinMaterial) }
            .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
            .clipShape(Capsule(style: .continuous))
    }

    private func tab(_ t: MainTabView.Tab, icon: String, label: String) -> some View {
        let isPublish = t == .publish
        let isSel = selected == t
        return Button {
            Motion.run(Motion.snap) { selected = t }
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: isPublish ? 22 : 17, weight: .semibold))
                    .symbolEffect(.bounce, value: isSel)
                Text(label)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSel ? Color.black : Theme.inkFaint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if isSel {
                    Capsule(style: .continuous)
                        .fill(Theme.brandGradient)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 10, y: 3)
                        .matchedGeometryEffect(id: "tabpill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }
}
