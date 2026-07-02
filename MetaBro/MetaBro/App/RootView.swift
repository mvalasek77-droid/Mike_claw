import SwiftUI

/// The five-tab hybrid shell. Uses the iOS 18+ `Tab` API so iPadOS renders
/// it as an adaptive sidebar (`.sidebarAdaptable`) while iPhone keeps the
/// standard bottom tab bar — no size-class branching required.
struct RootView: View {
    let container: AppContainer
    let onSignOut: () -> Void
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                FeedView(container: container)
            }
            Tab(AppTab.communities.title, systemImage: AppTab.communities.systemImage, value: AppTab.communities) {
                CommunitiesView(container: container)
            }
            Tab(AppTab.create.title, systemImage: AppTab.create.systemImage, value: AppTab.create) {
                ComposerView(feedService: container.feedService,
                             communityService: container.communityService)
            }
            Tab(AppTab.messages.title, systemImage: AppTab.messages.systemImage, value: AppTab.messages) {
                ConversationListView(service: container.messagingService,
                                    safetyService: container.safetyService)
            }
            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                ProfileView(container: container, onSignOut: onSignOut)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Tokens.Color.accent)
        .task { await container.pushNotificationService.requestAuthorization() }
    }
}
