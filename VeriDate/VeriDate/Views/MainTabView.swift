import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        TabView {
            DiscoveryView()
                .tabItem {
                    Label("Discover", systemImage: "heart")
                }

            MatchesView()
                .tabItem {
                    Label("Matches", systemImage: "person.2")
                }

            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person")
                }
        }
        .task {
            await session.keepPresenceUpdated()
        }
    }
}
