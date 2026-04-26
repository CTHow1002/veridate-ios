import SwiftUI

struct MatchesView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = MatchesViewModel()
    let navigationTitle: String

    init(navigationTitle: String = "Matches") {
        self.navigationTitle = navigationTitle
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.currentProfile?.verificationStatus != .verified {
                    ContentUnavailableView(
                        "Verification Required",
                        systemImage: "checkmark.seal",
                        description: Text("Only verified users can view matches.")
                    )
                } else if vm.isLoading {
                    ProgressView("Loading matches...")
                } else if let error = vm.errorMessage, vm.matches.isEmpty {
                    ContentUnavailableView("Could Not Load Matches", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if vm.matches.isEmpty {
                    ContentUnavailableView("No Matches Yet", systemImage: "heart", description: Text("When someone likes you back, they will appear here."))
                } else {
                    List(vm.matches) { row in
                        NavigationLink {
                            ChatThreadView(row: row)
                        } label: {
                            MatchRowView(row: row)
                        }
                    }
                    .refreshable {
                        await load()
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .task(id: session.currentUserId) {
                await load()
            }
        }
    }

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadMatches(userId: userId, currentProfile: session.currentProfile)
    }
}

private struct MatchRowView: View {
    let row: MatchRow

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(row.profile.fullName ?? "Verified User")
                    .font(.headline)

                Text(lastMessageText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        Group {
            if let urlString = row.profile.profilePhotoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.12))
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let age = row.profile.age.map { "\($0)" }
        let city = row.profile.city?.trimmingCharacters(in: .whitespacesAndNewlines)

        return [age, city]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
    }

    private var lastMessageText: String {
        guard let lastMessage = row.lastMessage else {
            return "Start the conversation"
        }

        return lastMessage.body
    }
}
