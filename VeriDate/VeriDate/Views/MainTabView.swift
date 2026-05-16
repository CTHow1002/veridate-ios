import SwiftUI
import PostgREST
import Supabase
import UIKit

extension Notification.Name {
    static let didOpenChatMatch = Notification.Name("DidOpenChatMatch")
    static let didCloseChatMatch = Notification.Name("DidCloseChatMatch")
}

struct MainTabView: View {
    @EnvironmentObject var session: SessionViewModel
    @AppStorage(NotificationPreferenceKey.inAppMessagesEnabled) private var inAppMessagesEnabled = true
    @AppStorage(NotificationPreferenceKey.messageAlertsEnabled) private var messageAlertsEnabled = true

    @StateObject private var matchListenerViewModel = DiscoveryViewModel()
    @State private var matchedProfile: Profile?
    @State private var pendingChatRow: MatchRow?
    @State private var selectedTab: MainTab = .discover
    @State private var knownMatchIds: Set<UUID> = []
    @State private var messageNotification: InAppMessageNotification?
    @State private var messageNotificationChannel: RealtimeChannelV2?
    @State private var messageNotificationTask: Task<Void, Never>?
    @State private var messageNotificationDismissTask: Task<Void, Never>?
    @State private var knownMessageNotificationIds: Set<UUID> = []
    @State private var activeChatMatchId: UUID?

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoveryView()
                .tabItem {
                    Label(AppLanguageManager.localized("mainTab.discover"), systemImage: "heart")
                }
                .tag(MainTab.discover)

            MatchesView(pendingChatRow: $pendingChatRow)
                .tabItem {
                    Label(AppLanguageManager.localized("mainTab.matches"), systemImage: "person.2")
                }
                .tag(MainTab.matches)

            ProfileView()
                .tabItem {
                    Label(AppLanguageManager.localized("mainTab.me"), systemImage: "person")
                }
                .tag(MainTab.profile)
        }
        .fullScreenCover(item: $matchedProfile) { profile in
            GlobalMatchCelebrationView(
                currentProfile: session.currentProfile,
                matchedProfile: profile,
                onClose: {
                    matchedProfile = nil
                },
                onSendMessage: {
                    Task {
                        await openChat(for: profile)
                    }
                    matchedProfile = nil
                }
            )
        }
        .overlay(alignment: .top) {
            if let messageNotification {
                InAppMessageNotificationBanner(notification: messageNotification) {
                    openMessageNotification(messageNotification)
                } onDismiss: {
                    dismissMessageNotification(id: messageNotification.id)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .id(messageNotification.id)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: messageNotification?.id)
        .task {
            await session.keepPresenceUpdated()
        }
        .task(id: session.currentUserId) {
            await startGlobalMatchListener()
        }
        .task(id: messageNotificationListenerKey) {
            await startGlobalMessageNotificationListener()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenChatMatch)) { notification in
            activeChatMatchId = notification.object as? UUID
            if let activeChatMatchId, messageNotification?.message.matchId == activeChatMatchId {
                if let notificationId = messageNotification?.id {
                    dismissMessageNotification(id: notificationId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didCloseChatMatch)) { notification in
            guard let closedMatchId = notification.object as? UUID else { return }
            if activeChatMatchId == closedMatchId {
                activeChatMatchId = nil
            }
        }
    }

    private var messageNotificationListenerKey: String {
        "\(session.currentUserId?.uuidString ?? "signed-out")-\(inAppMessagesEnabled)-\(messageAlertsEnabled)"
    }

    private func startGlobalMatchListener() async {
        guard let userId = session.currentUserId else { return }

        await markExistingMatchesAsKnown(for: userId)

        Task {
            await matchListenerViewModel.subscribeToMatches(userId: userId) { matchId, otherUserId in
                guard !knownMatchIds.contains(matchId) else { return }
                knownMatchIds.insert(matchId)
                Task { @MainActor in
                    await showMatchCelebration(for: otherUserId)
                }
            }
        }

        await pollForNewMatchesFallback(for: userId)
    }

    private func handleNewMatch(_ match: GlobalMatchLookupRow, currentUserId: UUID) async {
        guard !knownMatchIds.contains(match.id) else { return }
        knownMatchIds.insert(match.id)

        let otherUserId = match.userOneId == currentUserId ? match.userTwoId : match.userOneId
        await showMatchCelebration(for: otherUserId)
    }

    private func showMatchCelebration(for otherUserId: UUID) async {
        guard matchedProfile == nil else { return }

        do {
            let profile: Profile = try await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .eq("id", value: otherUserId)
                .single()
                .execute()
                .value

            matchedProfile = profile
        } catch {
            print("Failed to fetch matched profile globally:", error.localizedDescription)
        }
    }

    private func markExistingMatchesAsKnown(for userId: UUID) async {
        do {
            let matches = try await fetchMatches(for: userId)
            knownMatchIds = Set(matches.map(\.id))
        } catch {
            print("Failed to mark global existing matches:", error.localizedDescription)
        }
    }

    private func pollForNewMatchesFallback(for userId: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
                let matches = try await fetchMatches(for: userId)
                let newMatches = matches
                    .filter { !knownMatchIds.contains($0.id) }
                    .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }

                for match in newMatches {
                    await handleNewMatch(match, currentUserId: userId)
                }
            } catch is CancellationError {
                return
            } catch {
                print("Global match fallback poll failed:", error.localizedDescription)
            }
        }
    }

    private func fetchMatches(for userId: UUID) async throws -> [GlobalMatchLookupRow] {
        try await SupabaseManager.shared.client
            .from("matches")
            .select("id,user_one_id,user_two_id,created_at")
            .or("user_one_id.eq.\(userId.uuidString),user_two_id.eq.\(userId.uuidString)")
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    private func openChat(for profile: Profile) async {
        guard let userId = session.currentUserId else { return }

        do {
            let matches = try await fetchMatches(for: userId)

            guard let match = matches.first(where: {
                ($0.userOneId == userId && $0.userTwoId == profile.id) ||
                ($0.userTwoId == userId && $0.userOneId == profile.id)
            }) else {
                print("Match not found for chat")
                return
            }

            let realMatch = Match(
                id: match.id,
                userOneId: match.userOneId,
                userTwoId: match.userTwoId,
                createdAt: match.createdAt ?? ""
            )

            // Fetch the full profile so ChatThreadView has the same data as when opened from MatchesView.
            let fullProfile: Profile
            do {
                fullProfile = try await SupabaseManager.shared.client
                    .from("profiles")
                    .select()
                    .eq("id", value: profile.id)
                    .single()
                    .execute()
                    .value
            } catch {
                print("Failed to fetch full chat profile, using popup profile fallback:", error.localizedDescription)
                fullProfile = profile
            }

            let row = MatchRow(
                match: realMatch,
                profile: fullProfile,
                lastMessage: nil
            )

            await MainActor.run {
                selectedTab = .matches
                pendingChatRow = row
            }

        } catch {
            print("Failed to open chat:", error.localizedDescription)
        }
    }

    private func startGlobalMessageNotificationListener() async {
        messageNotificationTask?.cancel()
        messageNotificationTask = nil

        if let channel = messageNotificationChannel {
            await SupabaseManager.shared.client.removeChannel(channel)
            messageNotificationChannel = nil
        }

        guard inAppMessagesEnabled, messageAlertsEnabled else { return }
        guard let userId = session.currentUserId else { return }
        await markExistingIncomingMessagesAsKnown(for: userId)

        let channel = SupabaseManager.shared.client.channel("global-message-notifications-\(userId.uuidString)-\(UUID().uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages"
        )

        messageNotificationTask = Task {
            for await insertion in insertions {
                guard !Task.isCancelled else { return }
                await handleIncomingMessageRecord(insertion.record, currentUserId: userId)
            }
        }

        messageNotificationChannel = channel
        Task {
            do {
                try await channel.subscribeWithError()
            } catch {
                print("Failed to subscribe to in-app message notifications:", error.localizedDescription)
            }
        }

        await pollForIncomingMessageNotificationsFallback(for: userId)
    }

    private func handleIncomingMessageRecord(_ record: [String: Any?], currentUserId: UUID) async {
        guard inAppMessagesEnabled, messageAlertsEnabled else { return }
        guard let message = messageNotificationMessage(from: record) else { return }
        guard message.senderId != currentUserId else { return }
        guard !knownMessageNotificationIds.contains(message.id) else { return }
        guard message.matchId != activeChatMatchId else {
            knownMessageNotificationIds.insert(message.id)
            Task {
                await markMessageDelivered(matchId: message.matchId)
            }
            return
        }

        do {
            let match: GlobalMatchLookupRow = try await SupabaseManager.shared.client
                .from("matches")
                .select("id,user_one_id,user_two_id,created_at")
                .eq("id", value: message.matchId)
                .single()
                .execute()
                .value

            guard match.userOneId == currentUserId || match.userTwoId == currentUserId else {
                return
            }

            knownMessageNotificationIds.insert(message.id)
            Task {
                await markMessageDelivered(matchId: message.matchId)
            }

            let senderProfile: Profile = try await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .eq("id", value: message.senderId)
                .single()
                .execute()
                .value

            await showMessageNotification(message: message, senderProfile: senderProfile)
        } catch {
            print("Failed to prepare in-app message notification:", error.localizedDescription)
        }
    }

    private func markExistingIncomingMessagesAsKnown(for userId: UUID) async {
        do {
            let matches = try await fetchMatches(for: userId)
            var ids = Set<UUID>()

            for match in matches {
                if let message = try await fetchLatestMessage(matchId: match.id),
                   message.senderId != userId {
                    ids.insert(message.id)
                }
            }

            knownMessageNotificationIds = ids
        } catch {
            print("Failed to seed message notification fallback:", error.localizedDescription)
        }
    }

    private func pollForIncomingMessageNotificationsFallback(for userId: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(2))
                let matches = try await fetchMatches(for: userId)

                for match in matches {
                    guard let message = try await fetchLatestMessage(matchId: match.id),
                          message.senderId != userId,
                          message.matchId != activeChatMatchId,
                          !knownMessageNotificationIds.contains(message.id) else {
                        continue
                    }

                    knownMessageNotificationIds.insert(message.id)
                    await handleIncomingMessage(message, currentUserId: userId)
                }
            } catch is CancellationError {
                return
            } catch {
                print("Message notification fallback poll failed:", error.localizedDescription)
            }
        }
    }

    private func handleIncomingMessage(_ message: Message, currentUserId: UUID) async {
        guard inAppMessagesEnabled, messageAlertsEnabled else { return }
        guard message.senderId != currentUserId else { return }
        guard message.matchId != activeChatMatchId else { return }

        Task {
            await markMessageDelivered(matchId: message.matchId)
        }

        do {
            let senderProfile: Profile = try await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .eq("id", value: message.senderId)
                .single()
                .execute()
                .value

            await showMessageNotification(message: message, senderProfile: senderProfile)
        } catch {
            print("Failed to prepare fallback in-app message notification:", error.localizedDescription)
        }
    }

    private func fetchLatestMessage(matchId: UUID) async throws -> Message? {
        let messages: [Message] = try await SupabaseManager.shared.client
            .from("messages")
            .select()
            .eq("match_id", value: matchId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return messages.first
    }

    private func markMessageDelivered(matchId: UUID) async {
        struct ReceiptParams: Encodable {
            let p_match_id: UUID
        }

        do {
            try await SupabaseManager.shared.client
                .rpc("mark_match_messages_delivered", params: ReceiptParams(p_match_id: matchId))
                .execute()
        } catch {
            print("Failed to mark in-app notification message delivered:", error.localizedDescription)
        }
    }

    private func showMessageNotification(message: Message, senderProfile: Profile) async {
        let avatarImage = await notificationAvatarImage(for: senderProfile.profilePhotoURL)
        messageNotificationDismissTask?.cancel()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        messageNotification = InAppMessageNotification(
            message: message,
            senderProfile: senderProfile,
            senderPhotoPath: senderProfile.profilePhotoURL,
            senderAvatarImage: avatarImage,
            previewText: previewText(for: message)
        )

        messageNotificationDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                dismissMessageNotification(id: message.id)
            }
        }
    }

    private func notificationAvatarImage(for photoPath: String?) async -> UIImage? {
        guard let photoPath, !photoPath.isEmpty else { return nil }

        do {
            let url = try await ProfilePhotoService.shared.signedURL(for: photoPath)
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func openMessageNotification(_ notification: InAppMessageNotification) {
        messageNotificationDismissTask?.cancel()
        messageNotification = nil
        Task {
            await openChat(for: notification.senderProfile)
        }
    }

    private func dismissMessageNotification(id: UUID) {
        guard messageNotification?.id == id else { return }
        messageNotificationDismissTask?.cancel()
        messageNotification = nil
    }

    private func previewText(for message: Message) -> String {
        let trimmedBody = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            return trimmedBody
        }

        switch message.attachmentKind {
        case "image":
            return "Sent a photo"
        case "video":
            return "Sent a video"
        case "audio":
            return "Sent a voice message"
        default:
            return message.attachmentFileName ?? "Sent an attachment"
        }
    }

    private func messageNotificationMessage(from record: [String: Any?]) -> Message? {
        guard let idText = realtimeStringValue(recordValue(record, "id")),
              let id = UUID(uuidString: idText),
              let matchText = realtimeStringValue(recordValue(record, "match_id")),
              let matchId = UUID(uuidString: matchText),
              let senderText = realtimeStringValue(recordValue(record, "sender_id")),
              let senderId = UUID(uuidString: senderText),
              let createdAt = realtimeStringValue(recordValue(record, "created_at")) else {
            return nil
        }
        let body = realtimeStringValue(recordValue(record, "body")) ?? ""

        return Message(
            id: id,
            matchId: matchId,
            senderId: senderId,
            body: body,
            isRead: realtimeBoolValue(recordValue(record, "is_read")) ?? (realtimeStringValue(recordValue(record, "read_at")) != nil),
            deliveredAt: realtimeStringValue(recordValue(record, "delivered_at")),
            readAt: realtimeStringValue(recordValue(record, "read_at")),
            attachmentFilePath: realtimeStringValue(recordValue(record, "attachment_file_path")),
            attachmentFileName: realtimeStringValue(recordValue(record, "attachment_file_name")),
            attachmentContentType: realtimeStringValue(recordValue(record, "attachment_content_type")),
            attachmentKind: realtimeStringValue(recordValue(record, "attachment_kind")),
            attachmentGroupId: realtimeUUIDValue(recordValue(record, "attachment_group_id")),
            replyToMessageId: realtimeUUIDValue(recordValue(record, "reply_to_message_id")),
            editedAt: realtimeStringValue(recordValue(record, "edited_at")),
            deletedAt: realtimeStringValue(recordValue(record, "deleted_at")),
            createdAt: createdAt
        )
    }

    private func recordValue(_ record: [String: Any?], _ key: String) -> Any? {
        guard let value = record[key] else { return nil }
        return value
    }

    private func realtimeStringValue(_ value: Any?) -> String? {
        guard let unwrapped = unwrapOptional(value), !(unwrapped is NSNull) else { return nil }

        if let string = unwrapped as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return isNullText(trimmed) ? nil : trimmed
        }

        if let uuid = unwrapped as? UUID {
            return uuid.uuidString
        }

        let text = String(describing: unwrapped)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return isNullText(text) ? nil : text
    }

    private func realtimeBoolValue(_ value: Any?) -> Bool? {
        guard let unwrapped = unwrapOptional(value), !(unwrapped is NSNull) else { return nil }

        if let bool = unwrapped as? Bool {
            return bool
        }

        if let int = unwrapped as? Int {
            return int == 1
        }

        if let string = unwrapped as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) { return true }
            if ["false", "0", "no"].contains(normalized) { return false }
        }

        return nil
    }

    private func realtimeUUIDValue(_ value: Any?) -> UUID? {
        guard let text = realtimeStringValue(value) else { return nil }
        return UUID(uuidString: text)
    }

    private func isNullText(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "null"
            || normalized == "nil"
            || normalized == "<null>"
            || normalized == "optional(nil)"
            || normalized == "optional(<null>)"
    }

    private func unwrapOptional(_ value: Any?) -> Any? {
        guard let value else { return nil }

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }

        guard let child = mirror.children.first else {
            return nil
        }

        return unwrapOptional(child.value)
    }
}

private enum MainTab: Hashable {
    case discover
    case matches
    case profile
}

private struct GlobalMatchLookupRow: Codable, Identifiable {
    let id: UUID
    let userOneId: UUID
    let userTwoId: UUID
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userOneId = "user_one_id"
        case userTwoId = "user_two_id"
        case createdAt = "created_at"
    }
}

private struct InAppMessageNotification: Identifiable {
    let message: Message
    let senderProfile: Profile
    let senderPhotoPath: String?
    let senderAvatarImage: UIImage?
    let previewText: String

    var id: UUID {
        message.id
    }
}

private struct InAppMessageNotificationBanner: View {
    let notification: InAppMessageNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 12) {
                NotificationAvatarView(
                    image: notification.senderAvatarImage,
                    name: notification.senderProfile.publicName
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.senderProfile.publicName ?? "New message")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(notification.previewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationAvatarView: View {
    let image: UIImage?
    let name: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.pink.opacity(0.22), .red.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
    }

    private var initials: String {
        let words = (name ?? "")
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        let value = String(words).uppercased()
        return value.isEmpty ? "V" : value
    }
}

private struct GlobalMatchCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let currentProfile: Profile?
    let matchedProfile: Profile
    let onClose: () -> Void
    let onSendMessage: () -> Void

    @State private var photosVisible = false
    @State private var heartVisible = false
    @State private var copyVisible = false
    @State private var buttonsVisible = false
    @State private var heartPulse = false

    var body: some View {
        ZStack {
            MatchCelebrationBackground()

            VStack(spacing: 28) {
                Spacer(minLength: 48)

                photoPair
                    .padding(.top, 32)

                copyBlock

                Spacer()

                actionButtons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .task {
            await runAnimation()
        }
    }

    private var photoPair: some View {
        ZStack {
            HStack(spacing: -18) {
                MatchCelebrationAvatar(
                    profile: currentProfile,
                    fallbackSystemImage: "person.fill",
                    borderColor: .white
                )
                .offset(x: photosVisible || reduceMotion ? 0 : -180)
                .opacity(photosVisible || reduceMotion ? 1 : 0)

                MatchCelebrationAvatar(
                    profile: matchedProfile,
                    fallbackSystemImage: "heart.fill",
                    borderColor: .pink.opacity(0.95)
                )
                .offset(x: photosVisible || reduceMotion ? 0 : 180)
                .opacity(photosVisible || reduceMotion ? 1 : 0)
            }

            ZStack {
                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 72, height: 72)
                    .shadow(color: .pink.opacity(0.38), radius: 24, y: 10)

                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(heartPulse && !reduceMotion ? 1.10 : 1)
                    .animation(
                        .easeInOut(duration: 0.78).repeatForever(autoreverses: true),
                        value: heartPulse
                    )
            }
            .scaleEffect(heartVisible || reduceMotion ? 1 : 0.25)
            .opacity(heartVisible || reduceMotion ? 1 : 0)
        }
        .frame(height: 190)
    }

    private var copyBlock: some View {
        VStack(spacing: 10) {
            Text(AppLanguageManager.localized("matchCelebration.title"))
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.20), radius: 12, y: 6)

            Text(String.localizedStringWithFormat(AppLanguageManager.localized("matchCelebration.subtitleFormat"), matchedProfile.publicName ?? AppLanguageManager.localized("matchCelebration.thisUser")))
                .font(.headline)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .opacity(copyVisible || reduceMotion ? 1 : 0)
        .scaleEffect(copyVisible || reduceMotion ? 1 : 0.92)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onSendMessage()
            } label: {
                Label(AppLanguageManager.localized("matchCelebration.sendMessage"), systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

            Button {
                onClose()
            } label: {
                Text(AppLanguageManager.localized("matchCelebration.keepDiscovering"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.92))
            .background(.white.opacity(0.16), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            }
        }
        .opacity(buttonsVisible || reduceMotion ? 1 : 0)
        .offset(y: buttonsVisible || reduceMotion ? 0 : 18)
    }

    private func runAnimation() async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            photosVisible = true
            heartVisible = true
            copyVisible = true
            buttonsVisible = true
            return
        }

        withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
            photosVisible = true
        }

        try? await Task.sleep(for: .milliseconds(280))
        withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
            heartVisible = true
        }
        heartPulse = true

        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.28)) {
            copyVisible = true
        }

        try? await Task.sleep(for: .milliseconds(170))
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            buttonsVisible = true
        }
    }
}

private struct MatchCelebrationBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.10, blue: 0.42),
                    Color(red: 0.78, green: 0.08, blue: 0.36),
                    Color(red: 0.32, green: 0.04, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 34)
                .offset(x: -130, y: -220)

            Circle()
                .fill(.pink.opacity(0.34))
                .frame(width: 280, height: 280)
                .blur(radius: 44)
                .offset(x: 140, y: 180)

            ForEach(MatchCelebrationHeart.all) { heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: heart.size, weight: .bold))
                    .foregroundStyle(.white.opacity(heart.opacity))
                    .rotationEffect(.degrees(heart.rotation))
                    .offset(x: heart.x, y: heart.y)
            }
        }
    }
}

private struct MatchCelebrationHeart: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let rotation: Double

    static let all: [MatchCelebrationHeart] = [
        MatchCelebrationHeart(x: -142, y: -118, size: 18, opacity: 0.22, rotation: -18),
        MatchCelebrationHeart(x: 132, y: -72, size: 24, opacity: 0.18, rotation: 16),
        MatchCelebrationHeart(x: -112, y: 130, size: 28, opacity: 0.16, rotation: 12),
        MatchCelebrationHeart(x: 96, y: 240, size: 18, opacity: 0.20, rotation: -10),
        MatchCelebrationHeart(x: 8, y: -236, size: 14, opacity: 0.18, rotation: 8)
    ]
}

private struct MatchCelebrationAvatar: View {
    let profile: Profile?
    let fallbackSystemImage: String
    let borderColor: Color

    @State private var signedURL: URL?

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.20))
                .frame(width: 142, height: 142)
                .blur(radius: 10)

            avatarContent
                .frame(width: 132, height: 132)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 5)
                }
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
        }
        .task(id: profile?.profilePhotoURL) {
            await loadSignedURL()
        }
    }

    private var avatarContent: some View {
        ZStack {
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
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.white.opacity(0.86), .pink.opacity(0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: fallbackSystemImage)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.pink.opacity(0.82))
        }
    }

    private func loadSignedURL() async {
        signedURL = nil
        guard let path = profile?.profilePhotoURL, !path.isEmpty else { return }

        do {
            signedURL = try await ProfilePhotoService.shared.signedURL(for: path)
        } catch {
            signedURL = nil
        }
    }
}
