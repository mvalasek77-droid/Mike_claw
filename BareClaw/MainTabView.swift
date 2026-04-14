import SwiftUI

// MARK: - MainTabView
//
// Root tab container for BareClaw.
// Tabs: Home (0) | Chat (1) | Vibes (2) | You (3)
//
// Observes appState.currentMode — when it flips to .chat, programmatically
// jumps to tab 1 so any part of the app can trigger the chat screen.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Int = 0

    /// Forest green matches the home screen palette used throughout the app.
    private let tabTint = Color(hex: "#1E3932")

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Tab 0 — Home
            HomeView()
                .environmentObject(appState)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // MARK: Tab 1 — Chat
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }
                .tag(1)

            // MARK: Tab 2 — Vibes
            CompanionTikTokView()
                .environmentObject(appState)
                .tabItem {
                    Label("Vibes", systemImage: "play.square.stack.fill")
                }
                .tag(2)

            // MARK: Tab 3 — You
            YouPlaceholderView()
                .tabItem {
                    Label("You", systemImage: "person.fill")
                }
                .tag(3)
        }
        .tint(tabTint)
        // React to mode changes driven from anywhere in the app
        .onChange(of: appState.currentMode) { newMode in
            if newMode == .chat {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = 1
                }
            }
        }
    }
}

// MARK: - YouPlaceholderView

private struct YouPlaceholderView: View {
    private let bg        = Color(hex: "#F2F0EB")
    private let green     = Color(hex: "#1E3932")
    private let midText   = Color(hex: "#5C5C5C")
    private let gold      = Color(hex: "#CBA258")

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 24) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [green.opacity(0.10), green.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 96, height: 96)

                    Circle()
                        .strokeBorder(green.opacity(0.12), lineWidth: 1.5)
                        .frame(width: 96, height: 96)

                    Image(systemName: "person.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(green.opacity(0.45))
                }

                VStack(spacing: 6) {
                    Text("Your Profile")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(green)

                    Text("Coming soon")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(midText)
                }

                // Teaser pill
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(gold)

                    Text("Stats, achievements & more")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(gold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(gold.opacity(0.10))
                )
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    MainTabView()
        .environmentObject(AppState())
}
#endif
