import SwiftUI

struct MainTabView: View {
    @State private var tab: Tab = .home

    enum Tab: Hashable { case home, charts, publish, library, profile }

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

    var body: some View {
        HStack(spacing: 0) {
            tab(.home,    icon: "house.fill",            label: "Home")
            tab(.charts,  icon: "chart.bar.fill",        label: "Top 10")
            tab(.publish, icon: "plus.circle.fill",      label: "Publish")
            tab(.library, icon: "rectangle.stack.fill",  label: "Library")
            tab(.profile, icon: "person.fill",           label: "You")
        }
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.6)
                )
        }
        .frame(maxWidth: 480)
    }

    private func tab(_ t: MainTabView.Tab, icon: String, label: String) -> some View {
        let isPublish = t == .publish
        let selectedState = selected == t
        return Button {
            Motion.run(Motion.snap) { selected = t }
            Haptics.selection()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: isPublish ? 22 : 17, weight: .semibold))
                Text(label)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(selectedState ? Theme.accentSoft : Theme.inkFaint)
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedState ? .isSelected : [])
    }
}
