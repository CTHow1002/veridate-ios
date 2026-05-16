import SwiftUI

struct MatchesView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = MatchesViewModel()
    @Binding var pendingChatRow: MatchRow?
    @State private var navigationPath: [MatchRow] = []
    let navigationTitle: String

    init(
        navigationTitle: String = AppLanguageManager.localized("matches.title"),
        pendingChatRow: Binding<MatchRow?> = .constant(nil)
    ) {
        self.navigationTitle = navigationTitle
        self._pendingChatRow = pendingChatRow
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if session.currentProfile?.verificationStatus != .verified {
                    ContentUnavailableView(
                        AppLanguageManager.localized("matches.verificationRequired.title"),
                        systemImage: "checkmark.seal",
                        description: Text(AppLanguageManager.localized("matches.verificationRequired.description"))
                    )
                } else if vm.isLoading {
                    ProgressView(AppLanguageManager.localized("matches.loading"))
                } else if let error = vm.errorMessage, vm.matches.isEmpty {
                    ContentUnavailableView(AppLanguageManager.localized("matches.loadError.title"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else if vm.matches.isEmpty {
                    ContentUnavailableView(AppLanguageManager.localized("matches.empty.title"), systemImage: "heart", description: Text(AppLanguageManager.localized("matches.empty.description")))
                } else {
                    List(vm.matches) { row in
                        NavigationLink(value: row) {
                            MatchRowView(row: row)
                        }
                    }
                    .refreshable {
                        await load()
                    }
                }
            }
            .navigationDestination(for: MatchRow.self) { row in
                ChatThreadView(row: row)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: session.currentUserId) {
                await load()
                await keepMatchesSynced()
            }
            .onChange(of: pendingChatRow?.id) { _, _ in
                openPendingChatIfNeeded()
            }
            .onAppear {
                openPendingChatIfNeeded()
            }
        }
    }

    private func openPendingChatIfNeeded() {
        guard let row = pendingChatRow else { return }

        if navigationPath.last?.id != row.id {
            navigationPath.append(row)
        }

        pendingChatRow = nil
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

private enum MatchMessagePreviewPlaceholder {
    static let photo = "Photo"
    static let video = "Video"
}

private struct MatchRowView: View {
    @EnvironmentObject private var session: SessionViewModel
    let row: MatchRow

    var body: some View {
        HStack(spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.profile.publicName ?? AppLanguageManager.localized("matches.verifiedUser"))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var avatar: some View {
        MatchAvatarView(photoPath: row.profile.profilePhotoURL, name: row.profile.publicName ?? AppLanguageManager.localized("matches.verifiedUser"))
    }

    private var rowAccessibilityLabel: String {
        let name = row.profile.publicName ?? AppLanguageManager.localized("matches.verifiedUser")
        let detail = subtitle.isEmpty ? lastMessageText : "\(subtitle), \(lastMessageText)"
        return String.localizedStringWithFormat(AppLanguageManager.localized("matches.row.accessibilityLabelFormat"), name, detail)
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
        let age = row.profile.displayAge.map { "\($0)" }
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
            return AppLanguageManager.localized("matches.startConversation")
        }

        if lastMessage.deletedAt != nil {
            return AppLanguageManager.localized("chat_message_deleted")
        }

        let trimmedBody = lastMessage.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if lastMessage.attachmentKind == "image" {
            if trimmedBody.isEmpty || trimmedBody == MatchMessagePreviewPlaceholder.photo {
                return AppLanguageManager.localized("chat_photo_message")
            }
        }

        if lastMessage.attachmentKind == "video" {
            if trimmedBody.isEmpty || trimmedBody == MatchMessagePreviewPlaceholder.video {
                return AppLanguageManager.localized("chat_video_message")
            }
        }

        if lastMessage.attachmentKind == "audio" {
            return AppLanguageManager.localized("chat_voice_message")
        }

        if lastMessage.attachmentFilePath != nil {
            if let fileName = lastMessage.attachmentFileName?.trimmingCharacters(in: .whitespacesAndNewlines), !fileName.isEmpty {
                return fileName
            }
            return AppLanguageManager.localized("chat_attachment_message")
        }

        return trimmedBody.isEmpty ? AppLanguageManager.localized("matches.startConversation") : trimmedBody
    }

    private var presenceText: String {
        if isRecentlyOnline {
            return AppLanguageManager.localized("matches.presence.online")
        }

        guard let lastSeenAt = row.profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return AppLanguageManager.localized("matches.presence.offline")
        }

        return String(
            format: AppLanguageManager.localized("matches.presence.lastSeenFormat"),
            date.formatted(.relative(presentation: .named))
        )
    }

    private var isRecentlyOnline: Bool {
        guard row.profile.isOnline else { return false }
        guard let lastSeenAt = row.profile.lastSeenAt, let date = parseDate(lastSeenAt) else {
            return true
        }

        return Date().timeIntervalSince(date) < 45
    }

    private func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct MatchAvatarView: View {
    let photoPath: String?
    let name: String
    @State private var signedURL: URL?

    var body: some View {
        Group {
            if let signedURL {
                AsyncImage(url: signedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
        .accessibilityLabel(String.localizedStringWithFormat(AppLanguageManager.localized("matches.avatar.accessibilityLabelFormat"), name))
        .task(id: photoPath) {
            await loadSignedURL()
        }
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(.secondary.opacity(0.12))
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func loadSignedURL() async {
        signedURL = nil
        guard let photoPath, !photoPath.isEmpty else { return }

        do {
            signedURL = try await ProfilePhotoService.shared.signedURL(for: photoPath)
        } catch {
            signedURL = nil
        }
    }
}

private struct PresenceDot: View {
    let isOnline: Bool

    var body: some View {
        Circle()
            .fill(isOnline ? .green : .secondary.opacity(0.45))
            .frame(width: 8, height: 8)
            .accessibilityLabel(isOnline ? AppLanguageManager.localized("matches.presence.online") : AppLanguageManager.localized("matches.presence.offline"))
    }
}

struct MessageStatusTicks: View {
    let message: Message

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(statusColor)
            .accessibilityLabel(accessibilityText)
    }

    private var statusColor: Color {
        message.readAt != nil ? .blue : .secondary
    }

    private var systemImage: String {
        if message.readAt != nil {
            return "checkmark.circle.fill"
        }

        if message.deliveredAt != nil {
            return "checkmark.circle.fill"
        }

        return "checkmark.circle"
    }

    private var accessibilityText: String {
        if message.readAt != nil {
            return AppLanguageManager.localized("matches.messageStatus.read")
        }

        if message.deliveredAt != nil {
            return AppLanguageManager.localized("matches.messageStatus.delivered")
        }

        return AppLanguageManager.localized("matches.messageStatus.sent")
    }
}
