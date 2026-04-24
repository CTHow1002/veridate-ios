import SwiftUI

struct ChatListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Chats coming next", systemImage: "bubble.left.and.bubble.right")
                .navigationTitle("Chats")
        }
    }
}
