import SwiftUI

/// The five-tab hybrid shell. Tab bar floats on Liquid Glass (system-provided).
/// Home feed and Bro-hoods ship live; remaining tabs are honest placeholders
/// wired to the same design system, ready for later phases.
struct RootView: View {
    let container: AppContainer
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            FeedView(container: container)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            CommunitiesView(service: container.communityService)
                .tabItem { Label(AppTab.communities.title, systemImage: AppTab.communities.systemImage) }
                .tag(AppTab.communities)

            ForEach([AppTab.create, .messages, .profile], id: \.self) { tab in
                ComingSoonView(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .tint(Tokens.Color.accent)
    }
}

/// Honest placeholder for not-yet-built tabs — still on-brand and accessible,
/// never a blank screen.
private struct ComingSoonView: View {
    let tab: AppTab

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(tab.title, systemImage: tab.systemImage)
            } description: {
                Text("Coming in a later phase. The bros are working on it.")
            }
            .navigationTitle(tab.title)
        }
    }
}
