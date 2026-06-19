import SwiftUI

/// The five-tab hybrid shell. Tab bar floats on Liquid Glass (system-provided).
/// Home, Bro-hoods (+search), Post composer, and Profile ship live; Messages is
/// an honest placeholder for a later phase.
struct RootView: View {
    let container: AppContainer
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            FeedView(container: container)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            CommunitiesView(container: container)
                .tabItem { Label(AppTab.communities.title, systemImage: AppTab.communities.systemImage) }
                .tag(AppTab.communities)

            ComposerView(feedService: container.feedService,
                         communityService: container.communityService)
                .tabItem { Label(AppTab.create.title, systemImage: AppTab.create.systemImage) }
                .tag(AppTab.create)

            ComingSoonView(tab: .messages)
                .tabItem { Label(AppTab.messages.title, systemImage: AppTab.messages.systemImage) }
                .tag(AppTab.messages)

            ProfileView(container: container)
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
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
