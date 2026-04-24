import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DiscoveryView()
                .tabItem {
                    Label("Discover", systemImage: "heart")
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
