import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ProjectsLibraryView()
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }

            AIHubView()
                .tabItem { Label("AI Room", systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Palette.accent)
    }
}
