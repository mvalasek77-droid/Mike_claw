import SwiftUI

/// The five-tab hybrid shell. Tab bar floats on Liquid Glass (system-provided).
/// All five tabs ship live: Home feed, Bro-hoods (+ search), Post composer,
/// Messages, and Profile.
struct RootView: View {
    let container: AppContainer
    let onSignOut: () -> Void
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

            ConversationListView(service: container.messagingService,
                                  safetyService: container.safetyService)
                .tabItem { Label(AppTab.messages.title, systemImage: AppTab.messages.systemImage) }
                .tag(AppTab.messages)

            ProfileView(container: container, onSignOut: onSignOut)
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .tint(Tokens.Color.accent)
        .task { await container.pushNotificationService.requestAuthorization() }
    }
}
