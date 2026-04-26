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
                await keepMatchesSynced()
            }
        }
    }

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadMatches(userId: userId, currentProfile: session.currentProfile)
    }

    private func keepMatchesSynced() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))

            guard !Task.isCancelled else {
                return
            }

            await load()
        }
    }
}

private struct MatchRowView: View {
    @EnvironmentObject private var session: SessionViewModel
    let row: MatchRow

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.profile.fullName ?? "Verified User")
                        .font(.headline)

                    PresenceDot(isOnline: isRecentlyOnline)
                }

                HStack(spacing: 4) {
                    if let lastMessage = row.lastMessage,
                       let currentUserId = session.currentUserId,
                       lastMessage.senderId == currentUserId {
                        MessageStatusTicks(message: lastMessage)
                    }

                    Text(lastMessageText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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

        return [age, city, presenceText]
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

    private var presenceText: String {
        if isRecentlyOnline {
            return "Online"
        }

        guard let lastSeenAt = row.profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return "Offline"
        }

        return "Last seen \(date.formatted(.relative(presentation: .named)))"
    }

    private var isRecentlyOnline: Bool {
        guard row.profile.isOnline else { return false }
        guard let lastSeenAt = row.profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return true
        }

        return Date().timeIntervalSince(date) < 90
    }

    private func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct PresenceDot: View {
    let isOnline: Bool

    var body: some View {
        Circle()
            .fill(isOnline ? .green : .secondary.opacity(0.45))
            .frame(width: 8, height: 8)
            .accessibilityLabel(isOnline ? "Online" : "Offline")
    }
}

struct MessageStatusTicks: View {
    let message: Message

    var body: some View {
        HStack(spacing: -4) {
            ForEach(0..<tickCount, id: \.self) { _ in
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .foregroundStyle(statusColor)
        .accessibilityLabel(accessibilityText)
    }

    private var statusColor: Color {
        message.isRead || message.readAt != nil ? .blue : .secondary
    }

    private var tickCount: Int {
        message.deliveredAt != nil || message.isRead || message.readAt != nil ? 2 : 1
    }

    private var accessibilityText: String {
        if message.isRead || message.readAt != nil {
            return "Read"
        }

        if message.deliveredAt != nil {
            return "Delivered"
        }

        return "Sent"
    }
}
