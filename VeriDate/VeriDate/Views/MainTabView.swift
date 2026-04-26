import SwiftUI

struct MainTabView: View {
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

            ChatListView()
                .tabItem {
                    Label("Chats", systemImage: "message")
                }

            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person")
                }
        }
    }
}
