import Combine
import Foundation
import Supabase

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [Message] = [] {
        didSet {
            buildChatItems()
        }
    }
    enum ChatItem: Identifiable {
        case date(Date)
        case message(Message, isGroupedWithPrevious: Bool, isGroupedWithNext: Bool)

        var id: String {
            switch self {
            case .date(let date):
                return "date-\(date.timeIntervalSince1970)"
            case .message(let message, _, _):
                return message.id.uuidString
            }
        }
    }

    @Published var chatItems: [ChatItem] = []
    private func buildChatItems() {
        var items: [ChatItem] = []

        var i = messages.startIndex
        while i < messages.endIndex {
            let message = messages[i]

            // Date separator
            if i == 0 || !isSameDay(messages[i - 1], message) {
                if let date = parseDate(message.createdAt) {
                    items.append(.date(date))
                }
            }

            let isGroupedPrev = i > 0 && canGroup(messages[i - 1], message)
            let isGroupedNext = i < messages.count - 1 && canGroup(message, messages[i + 1])
            items.append(.message(message, isGroupedWithPrevious: isGroupedPrev, isGroupedWithNext: isGroupedNext))
            i += 1
        }

        chatItems = items
    }

    private func canGroup(_ first: Message, _ second: Message) -> Bool {
        guard first.senderId == second.senderId else { return false }

        guard let firstDate = parseDate(first.createdAt),
              let secondDate = parseDate(second.createdAt) else { return false }

        return abs(secondDate.timeIntervalSince(firstDate)) <= 300
    }

    private func isSameDay(_ first: Message, _ second: Message) -> Bool {
        guard let firstDate = parseDate(first.createdAt),
              let secondDate = parseDate(second.createdAt) else { return false }

        return Calendar.current.isDate(firstDate, inSameDayAs: secondDate)
    }

    private func parseDate(_ value: String) -> Date? {
        sharedISOFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func isRecentlyOnline(_ profile: Profile) -> Bool {
        guard profile.isOnline else { return false }
        guard let lastSeenAt = profile.lastSeenAt,
              let date = parseDate(lastSeenAt) else {
            return true
        }

        return Date().timeIntervalSince(date) < 45
    }
    @Published var otherProfile: Profile?
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isUploadingAttachment = false
    @Published var isBlocked = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?
    @Published var isOtherUserTyping: Bool = false
    @Published var isOtherUserPresent: Bool = false
    @Published var pendingMessageIds = Set<UUID>()
    @Published var failedMessageIds = Set<UUID>()
    @Published var reactionsByMessageId: [UUID: [MessageReaction]] = [:]

    var currentUserId: UUID?
    private var lastReadReceiptUpdateAt: Date?

    private struct FailedMessageDraft {
        let body: String
        let match: Match
        let userId: UUID
        let replyToMessageId: UUID?
    }

    private var failedMessageDrafts: [UUID: FailedMessageDraft] = [:]

    private let supabase = SupabaseManager.shared.client
    private var messageChannel: RealtimeChannelV2?
    private var subscribedMessagesMatchId: UUID?
    private var messageListenerTask: Task<Void, Never>?
    private var messageUpdateTask: Task<Void, Never>?
    private var reactionChannel: RealtimeChannelV2?
    private var subscribedReactionMatchId: UUID?
    private var reactionInsertTask: Task<Void, Never>?
    private var reactionUpdateTask: Task<Void, Never>?
    private var reactionDeleteTask: Task<Void, Never>?

    private var profileChannel: RealtimeChannelV2?
    private var subscribedProfileUserId: UUID?
    private var profileUpdateTask: Task<Void, Never>?

    // Realtime typing properties
    private var typingChannel: RealtimeChannelV2?
    private var subscribedTypingMatchId: UUID?
    private var typingListenerTask: Task<Void, Never>?
    private var typingUpdateTask: Task<Void, Never>?
    private var typingExpiryTask: Task<Void, Never>?
    private var lastTypingSignalAt: Date?

    func setInitialProfile(_ profile: Profile) {
        if otherProfile == nil {
            otherProfile = profile
        }
    }

    func loadOtherUserProfile(match: Match, currentUserId: UUID) async {
        let otherUserId = match.otherUserId(for: currentUserId)

        do {
            if let profile = try await fetchProfile(userId: otherUserId) {
                self.otherProfile = profile
                self.isOtherUserPresent = isRecentlyOnline(profile)
            }
        } catch {
            print("Failed to load other user profile:", error.localizedDescription)
        }
    }

    func loadMessages(match: Match, userId: UUID, currentProfile: Profile?) async {
        self.currentUserId = userId
        guard currentProfile?.verificationStatus == .verified else {
            messages = []
            errorMessage = AppLanguageManager.localized("chat_error_verified_users_only_message_matches")
            return
        }

        guard match.includes(userId: userId) else {
            messages = []
            errorMessage = AppLanguageManager.localized("chat_error_message_after_match_only")
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let fetchedProfile = try await fetchProfile(userId: match.otherUserId(for: userId)) ?? otherProfile
            let blocked = try await hasBlockBetween(match: match)
            let loadedMessages = try await fetchMessages(matchId: match.id)

            otherProfile = fetchedProfile
            if let fetchedProfile {
                isOtherUserPresent = isRecentlyOnline(fetchedProfile)
            }
            isBlocked = blocked
            messages = loadedMessages
            await loadReactions(matchId: match.id)
            isLoading = false

            Task { [weak self] in
                guard let self else { return }
                await self.subscribeToMessages(matchId: match.id)
                await self.subscribeToReactions(matchId: match.id)
                if let fetchedProfile {
                    await self.subscribeToProfileUpdates(userId: fetchedProfile.id)
                }
            }
        } catch {
            isLoading = false
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_load_messages_format"), error.localizedDescription)
        }
    }

    func refreshMessages(matchId: UUID) async -> Bool {
        do {
            let refreshedMessages = try await fetchMessages(matchId: matchId)
            guard refreshedMessages != messages else {
                return false
            }

            replaceWithServerMessages(refreshedMessages)
            return true
        } catch {
            if messages.isEmpty {
                errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_refresh_messages_format"), error.localizedDescription)
            }
            return false
        }
    }

    func refreshTypingStatus(matchId: UUID) async {
        guard let currentUserId else {
            isOtherUserTyping = false
            return
        }

        struct TypingRow: Decodable {
            let userId: UUID
            let isTyping: Bool
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case isTyping = "is_typing"
                case updatedAt = "updated_at"
            }
        }

        do {
            let rows: [TypingRow] = try await supabase
                .from("chat_typing")
                .select("user_id,is_typing,updated_at")
                .eq("match_id", value: matchId)
                .neq("user_id", value: currentUserId)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let row = rows.first,
                  let updatedAt = parseDate(row.updatedAt) else {
                isOtherUserTyping = false
                return
            }

            isOtherUserTyping = row.isTyping && Date().timeIntervalSince(updatedAt) < 3.5
        } catch {
            // Keep the current realtime-driven state when the fallback read fails.
        }
    }

    func refreshOtherProfile(match: Match) async {
        guard let currentUserId else { return }
        let otherUserId = match.otherUserId(for: currentUserId)

        do {
            guard let profile = try await fetchProfile(userId: otherUserId) else { return }
            otherProfile = profile
            isOtherUserPresent = isRecentlyOnline(profile)
        } catch {
            // Keep the existing presence state when a short fallback read fails.
        }
    }

    func sendMessage(
        body: String,
        match: Match,
        userId: UUID,
        currentProfile: Profile?,
        replyToMessageId: UUID? = nil
    ) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentProfile?.verificationStatus == .verified else {
            errorMessage = AppLanguageManager.localized("chat_error_verified_users_only_send_messages")
            return false
        }

        guard match.includes(userId: userId) else {
            errorMessage = AppLanguageManager.localized("chat_error_message_after_match_only")
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = AppLanguageManager.localized("chat_error_type_message_before_sending")
            return false
        }


        struct NewMessage: Encodable {
            let match_id: UUID
            let sender_id: UUID
            let body: String
            let reply_to_message_id: UUID?
        }

        let temporaryMessageId = UUID()
        let temporaryMessage = Message(
            id: temporaryMessageId,
            matchId: match.id,
            senderId: userId,
            body: trimmedBody,
            isRead: false,
            deliveredAt: nil,
            readAt: nil,
            attachmentFilePath: nil,
            attachmentFileName: nil,
            attachmentContentType: nil,
            attachmentKind: nil,
            attachmentGroupId: nil,
            replyToMessageId: replyToMessageId,
            editedAt: nil,
            deletedAt: nil,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        messages.append(temporaryMessage)
        pendingMessageIds.insert(temporaryMessageId)
        Task { [weak self] in
            guard let self else { return }
            do {
                if try await self.hasBlockBetween(match: match) {
                    await MainActor.run {
                        self.isBlocked = true
                        self.errorMessage = AppLanguageManager.localized("chat_error_messaging_unavailable_blocked")
                    }
                }
            } catch {
                // Ignore block check failure when offline to allow retry flow
            }
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let inserted: [Message] = try await supabase
                .from("messages")
                .insert(NewMessage(match_id: match.id, sender_id: userId, body: trimmedBody, reply_to_message_id: replyToMessageId))
                .select()
                .execute()
                .value

            if let confirmedMessage = inserted.first {
                pendingMessageIds.remove(temporaryMessageId)
                if let index = messages.firstIndex(where: { $0.id == temporaryMessageId }) {
                    messages[index] = confirmedMessage
                } else if !messages.contains(where: { $0.id == confirmedMessage.id }) {
                    messages.append(confirmedMessage)
                }
            } else {
                pendingMessageIds.remove(temporaryMessageId)
                messages.removeAll { $0.id == temporaryMessageId }
            }

            return true
        } catch {
            pendingMessageIds.remove(temporaryMessageId)
            failedMessageIds.insert(temporaryMessageId)
            failedMessageDrafts[temporaryMessageId] = FailedMessageDraft(
                body: trimmedBody,
                match: match,
                userId: userId,
                replyToMessageId: replyToMessageId
            )
            errorMessage = AppLanguageManager.localized("chat_error_send_message_retry")
            return false
        }
    }

    func retryFailedMessage(_ message: Message, currentProfile: Profile?) async -> Bool {
        guard failedMessageIds.contains(message.id),
              let draft = failedMessageDrafts[message.id] else {
            return false
        }

        guard currentProfile?.verificationStatus == .verified else {
            errorMessage = AppLanguageManager.localized("chat_error_verified_users_only_send_messages")
            return false
        }

        pendingMessageIds.insert(message.id)
        failedMessageIds.remove(message.id)
        errorMessage = nil

        struct NewMessage: Encodable {
            let match_id: UUID
            let sender_id: UUID
            let body: String
            let reply_to_message_id: UUID?
        }

        do {
            let inserted: [Message] = try await supabase
                .from("messages")
                .insert(
                    NewMessage(
                        match_id: draft.match.id,
                        sender_id: draft.userId,
                        body: draft.body,
                        reply_to_message_id: draft.replyToMessageId
                    )
                )
                .select()
                .execute()
                .value

            pendingMessageIds.remove(message.id)
            failedMessageDrafts.removeValue(forKey: message.id)

            if let confirmedMessage = inserted.first {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = confirmedMessage
                } else if !messages.contains(where: { $0.id == confirmedMessage.id }) {
                    messages.append(confirmedMessage)
                }
            } else {
                messages.removeAll { $0.id == message.id }
            }

            return true
        } catch {
            pendingMessageIds.remove(message.id)
            failedMessageIds.insert(message.id)
            failedMessageDrafts[message.id] = draft
            errorMessage = AppLanguageManager.localized("chat_error_still_could_not_send")
            return false
        }
    }

    func discardFailedMessage(_ message: Message) {
        pendingMessageIds.remove(message.id)
        failedMessageIds.remove(message.id)
        failedMessageDrafts.removeValue(forKey: message.id)
        messages.removeAll { $0.id == message.id }
    }

    func sendAttachment(
        _ attachment: ChatAttachmentFile,
        match: Match,
        userId: UUID,
        currentProfile: Profile?,
        body overrideBody: String? = nil,
        attachmentGroupId: UUID? = nil
    ) async -> Bool {
        guard currentProfile?.verificationStatus == .verified else {
            errorMessage = AppLanguageManager.localized("chat_error_verified_users_only_send_attachments")
            return false
        }

        guard match.includes(userId: userId) else {
            errorMessage = AppLanguageManager.localized("chat_error_attachment_after_match_only")
            return false
        }

        do {
            if try await hasBlockBetween(match: match) {
                isBlocked = true
                errorMessage = AppLanguageManager.localized("chat_error_messaging_unavailable_blocked")
                return false
            }
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_check_message_safety_format"), error.localizedDescription)
            return false
        }

        struct NewAttachmentMessage: Encodable {
            let match_id: UUID
            let sender_id: UUID
            let body: String
            let attachment_file_path: String
            let attachment_file_name: String
            let attachment_content_type: String
            let attachment_kind: String
            let attachment_group_id: UUID?
            let reply_to_message_id: UUID?
        }

        isUploadingAttachment = true
        errorMessage = nil
        defer { isUploadingAttachment = false }

        let path: String
        do {
            path = try await ChatAttachmentService.shared.uploadAttachment(
                matchId: match.id,
                senderId: userId,
                attachment: attachment
            )
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_upload_attachment_format"), error.localizedDescription)
            return false
        }

        do {
            let body = clean(overrideBody) ?? defaultAttachmentBody(for: attachment)
            let temporaryMessageId = UUID()
            let temporaryMessage = Message(
                id: temporaryMessageId,
                matchId: match.id,
                senderId: userId,
                body: body,
                isRead: false,
                deliveredAt: nil,
                readAt: nil,
                attachmentFilePath: path,
                attachmentFileName: attachment.fileName,
                attachmentContentType: attachment.contentType,
                attachmentKind: attachment.kind,
                attachmentGroupId: attachmentGroupId,
                replyToMessageId: nil,
                editedAt: nil,
                deletedAt: nil,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )

            messages.append(temporaryMessage)
            pendingMessageIds.insert(temporaryMessageId)

            let inserted: [Message] = try await supabase
                .from("messages")
                .insert(
                    NewAttachmentMessage(
                        match_id: match.id,
                        sender_id: userId,
                        body: body,
                        attachment_file_path: path,
                        attachment_file_name: attachment.fileName,
                        attachment_content_type: attachment.contentType,
                        attachment_kind: attachment.kind,
                        attachment_group_id: attachmentGroupId,
                        reply_to_message_id: nil
                    )
                )
                .select()
                .execute()
                .value

            pendingMessageIds.remove(temporaryMessageId)
            if let confirmedMessage = inserted.first {
                if let index = messages.firstIndex(where: { $0.id == temporaryMessageId }) {
                    messages[index] = confirmedMessage
                } else if !messages.contains(where: { $0.id == confirmedMessage.id }) {
                    messages.append(confirmedMessage)
                }
            } else {
                messages.removeAll { $0.id == temporaryMessageId }
            }

            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_create_attachment_message_format"), error.localizedDescription)
            return false
        }
    }

    func blockUser(match: Match, blockedUserId: UUID, userId: UUID, reason: String?) async {
        guard match.includes(userId: userId), match.includes(userId: blockedUserId) else {
            errorMessage = AppLanguageManager.localized("chat_error_block_matched_users_only")
            return
        }

        struct BlockPayload: Encodable {
            let blocker_user_id: UUID
            let blocked_user_id: UUID
            let match_id: UUID
            let reason: String?
        }

        struct LegacyBlockPayload: Encodable {
            let blocker_id: UUID
            let blocked_id: UUID
            let match_id: UUID
            let reason: String?
        }

        do {
            let cleanReason = clean(reason)
            do {
                try await supabase
                    .from("blocks")
                    .upsert(
                        BlockPayload(
                            blocker_user_id: userId,
                            blocked_user_id: blockedUserId,
                            match_id: match.id,
                            reason: cleanReason
                        ),
                        onConflict: "blocker_user_id,blocked_user_id"
                    )
                    .execute()
            } catch {
                try await supabase
                    .from("blocks")
                    .insert(
                        LegacyBlockPayload(
                            blocker_id: userId,
                            blocked_id: blockedUserId,
                            match_id: match.id,
                            reason: cleanReason
                        )
                    )
                    .execute()
            }

            isBlocked = true
            actionMessage = AppLanguageManager.localized("chat_action_user_blocked")
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_block_user_format"), error.localizedDescription)
        }
    }

    func reportUser(match: Match, reportedUserId: UUID, userId: UUID, reason: String) async {
        guard match.includes(userId: userId), match.includes(userId: reportedUserId) else {
            errorMessage = AppLanguageManager.localized("chat_error_report_matched_users_only")
            return
        }

        guard let reason = clean(reason) else {
            errorMessage = AppLanguageManager.localized("chat_error_report_reason_required")
            return
        }

        struct ReportPayload: Encodable {
            let reporter_user_id: UUID
            let reported_user_id: UUID
            let match_id: UUID
            let reason: String
        }

        do {
            try await supabase
                .from("reports")
                .insert(ReportPayload(reporter_user_id: userId, reported_user_id: reportedUserId, match_id: match.id, reason: reason))
                .execute()

            actionMessage = AppLanguageManager.localized("chat_action_report_submitted")
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_submit_report_format"), error.localizedDescription)
        }
    }

    func markMessagesRead(matchId: UUID) async {
        // Do not rely on local `messages` here.
        // For a live INSERT, the new incoming message may not be in the local array yet.
        guard currentUserId != nil else { return }
        let shouldSendReadReceipts = UserDefaults.standard.object(forKey: PrivacyPreferenceKey.sendReadReceipts) as? Bool ?? true
        guard shouldSendReadReceipts else { return }
        lastReadReceiptUpdateAt = Date()

        struct ReceiptParams: Encodable {
            let p_match_id: UUID
        }

        do {
            try await supabase
                .rpc("mark_match_messages_read", params: ReceiptParams(p_match_id: matchId))
                .execute()

            let refreshedMessages = try await fetchMessages(matchId: matchId)
            replaceWithServerMessages(refreshedMessages)
        } catch {
            if (error as? CancellationError) != nil {
                return
            }
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_mark_read_format"), error.localizedDescription)
        }
    }

    func editMessage(_ message: Message, newBody: String, userId: UUID) async -> Bool {
        guard message.senderId == userId else {
            errorMessage = AppLanguageManager.localized("chat_error_edit_own_messages_only")
            return false
        }

        guard message.deletedAt == nil else {
            errorMessage = AppLanguageManager.localized("chat_error_deleted_messages_cannot_be_edited")
            return false
        }

        guard message.attachmentKind != "audio" else {
            errorMessage = AppLanguageManager.localized("chat_error_voice_messages_cannot_be_edited")
            return false
        }

        let body: String
        if message.attachmentFilePath != nil {
            body = clean(newBody) ?? defaultAttachmentBody(for: message)
        } else if let cleanBody = clean(newBody) {
            body = cleanBody
        } else {
            errorMessage = AppLanguageManager.localized("chat_error_edited_message_empty")
            return false
        }

        struct EditPayload: Encodable {
            let body: String
            let edited_at: String
        }

        do {
            let updated: [Message] = try await supabase
                .from("messages")
                .update(EditPayload(body: body, edited_at: ISO8601DateFormatter().string(from: Date())))
                .eq("id", value: message.id)
                .eq("sender_id", value: userId)
                .select()
                .execute()
                .value

            if let updatedMessage = updated.first {
                appendOrReplace(updatedMessage)
            }

            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_edit_message_format"), error.localizedDescription)
            return false
        }
    }

    func deleteMessage(_ message: Message, userId: UUID) async -> Bool {
        guard message.senderId == userId else {
            errorMessage = AppLanguageManager.localized("chat_error_delete_own_messages_only")
            return false
        }

        struct DeletePayload: Encodable {
            let body: String
            let deleted_at: String
            let attachment_file_path: String? = nil
            let attachment_file_name: String? = nil
            let attachment_content_type: String? = nil
            let attachment_kind: String? = nil
            let attachment_group_id: UUID? = nil

            enum CodingKeys: String, CodingKey {
                case body
                case deleted_at
                case attachment_file_path
                case attachment_file_name
                case attachment_content_type
                case attachment_kind
                case attachment_group_id
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(body, forKey: .body)
                try container.encode(deleted_at, forKey: .deleted_at)
                try container.encodeNil(forKey: .attachment_file_path)
                try container.encodeNil(forKey: .attachment_file_name)
                try container.encodeNil(forKey: .attachment_content_type)
                try container.encodeNil(forKey: .attachment_kind)
                try container.encodeNil(forKey: .attachment_group_id)
            }
        }

        do {
            let updated: [Message] = try await supabase
                .from("messages")
                .update(
                    DeletePayload(
                        body: AppLanguageManager.localized("chat_message_deleted_body"),
                        deleted_at: ISO8601DateFormatter().string(from: Date())
                    )
                )
                .eq("id", value: message.id)
                .eq("sender_id", value: userId)
                .select()
                .execute()
                .value

            if let updatedMessage = updated.first {
                appendOrReplace(updatedMessage)
            }

            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_delete_message_format"), error.localizedDescription)
            return false
        }
    }

    func setReaction(_ emoji: String, for message: Message, userId: UUID) async -> Bool {
        guard !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        struct ReactionPayload: Encodable {
            let message_id: UUID
            let match_id: UUID
            let user_id: UUID
            let emoji: String
        }

        do {
            let reactions: [MessageReaction] = try await supabase
                .from("message_reactions")
                .upsert(
                    ReactionPayload(message_id: message.id, match_id: message.matchId, user_id: userId, emoji: emoji),
                    onConflict: "message_id,user_id"
                )
                .select()
                .execute()
                .value

            if let reaction = reactions.first {
                appendOrReplace(reaction)
            }

            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("chat_error_react_message_format"), error.localizedDescription)
            return false
        }
    }

    private func markMessagesReadIfNeeded(matchId: UUID) async {
        if let lastReadReceiptUpdateAt,
           Date().timeIntervalSince(lastReadReceiptUpdateAt) < 2 {
            return
        }

        await markMessagesRead(matchId: matchId)
    }

    private func fetchMessages(matchId: UUID) async throws -> [Message] {
        try await supabase
            .from("messages")
            .select()
            .eq("match_id", value: matchId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    private func fetchReactions(matchId: UUID) async throws -> [MessageReaction] {
        try await supabase
            .from("message_reactions")
            .select()
            .eq("match_id", value: matchId)
            .execute()
            .value
    }

    private func loadReactions(matchId: UUID) async {
        do {
            let reactions = try await fetchReactions(matchId: matchId)
            reactionsByMessageId = Dictionary(grouping: reactions, by: \.messageId)
        } catch {
            if errorMessage == nil {
                errorMessage = AppLanguageManager.localized("chat_error_reactions_could_not_load")
            }
        }
    }

    private func fetchProfile(userId: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        return profiles.first
    }

    private func hasBlockBetween(match: Match) async throws -> Bool {
        struct BlockRow: Decodable {
            let id: UUID
        }

        let blocks: [BlockRow] = try await supabase
            .from("blocks")
            .select("id")
            .or(
                "and(blocker_user_id.eq.\(match.userOneId.uuidString),blocked_user_id.eq.\(match.userTwoId.uuidString)),and(blocker_user_id.eq.\(match.userTwoId.uuidString),blocked_user_id.eq.\(match.userOneId.uuidString))"
            )
            .limit(1)
            .execute()
            .value

        if !blocks.isEmpty {
            return true
        }

        let oldBlocks: [BlockRow] = (try? await supabase
            .from("blocks")
            .select("id")
            .or(
                "and(blocker_id.eq.\(match.userOneId.uuidString),blocked_id.eq.\(match.userTwoId.uuidString)),and(blocker_id.eq.\(match.userTwoId.uuidString),blocked_id.eq.\(match.userOneId.uuidString))"
            )
            .limit(1)
            .execute()
            .value) ?? []

        if !oldBlocks.isEmpty {
            return true
        }

        let legacyBlocks: [BlockRow] = (try? await supabase
            .from("user_blocks")
            .select("id")
            .or(
                "and(blocker_user_id.eq.\(match.userOneId.uuidString),blocked_user_id.eq.\(match.userTwoId.uuidString)),and(blocker_user_id.eq.\(match.userTwoId.uuidString),blocked_user_id.eq.\(match.userOneId.uuidString))"
            )
            .limit(1)
            .execute()
            .value) ?? []

        return !legacyBlocks.isEmpty
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func defaultAttachmentBody(for attachment: ChatAttachmentFile) -> String {
        switch attachment.kind {
        case "image":
            return AppLanguageManager.localized("chat_attachment_body_photo")
        case "video":
            return AppLanguageManager.localized("chat_attachment_body_video")
        case "audio":
            return AppLanguageManager.localized("chat_attachment_body_voice_message")
        default:
            return attachment.fileName
        }
    }

    private func defaultAttachmentBody(for message: Message) -> String {
        switch message.attachmentKind {
        case "image":
            return AppLanguageManager.localized("chat_attachment_body_photo")
        case "video":
            return AppLanguageManager.localized("chat_attachment_body_video")
        case "audio":
            return AppLanguageManager.localized("chat_attachment_body_voice_message")
        default:
            return message.attachmentFileName ?? AppLanguageManager.localized("chat_attachment_body_attachment")
        }
    }

    func subscribeToMessages(matchId: UUID) async {
        if subscribedMessagesMatchId == matchId, messageChannel != nil {
            return
        }

        messageListenerTask?.cancel()
        messageListenerTask = nil
        messageUpdateTask?.cancel()
        messageUpdateTask = nil

        if let channel = messageChannel {
            await supabase.removeChannel(channel)
        }

        messageChannel = nil
        subscribedMessagesMatchId = nil

        let channel = supabase.channel("messages-listener-\(matchId.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages"
        )
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "messages"
        )

        messageListenerTask = Task { [weak self] in
            for await insertion in insertions {
                guard !Task.isCancelled else { return }

                let record = insertion.record

                guard let self else { return }

                guard let incomingMatchId = self.realtimeStringValue(self.recordValue(record, "match_id")) else {
                    continue
                }

                guard incomingMatchId.lowercased() == matchId.uuidString.lowercased() else {
                    continue
                }

                guard let message = self.message(from: record) else {
                    continue
                }

                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.appendOrReplace(message)
                }

            }
        }

        messageUpdateTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled else { return }

                let record = update.record

                guard let self else { return }

                guard let incomingMatchId = self.realtimeStringValue(self.recordValue(record, "match_id")) else {
                    continue
                }

                guard incomingMatchId.lowercased() == matchId.uuidString.lowercased() else {
                    continue
                }

                if let message = self.message(from: record) {
                    self.appendOrReplace(message)
                }
            }
        }

        do {
            try await channel.subscribeWithError()
            messageChannel = channel
            subscribedMessagesMatchId = matchId
        } catch {
            // ignore
        }
    }

    func subscribeToReactions(matchId: UUID) async {
        if subscribedReactionMatchId == matchId, reactionChannel != nil {
            return
        }

        reactionInsertTask?.cancel()
        reactionInsertTask = nil
        reactionUpdateTask?.cancel()
        reactionUpdateTask = nil
        reactionDeleteTask?.cancel()
        reactionDeleteTask = nil

        if let channel = reactionChannel {
            await supabase.removeChannel(channel)
        }

        reactionChannel = nil
        subscribedReactionMatchId = nil

        let channel = supabase.channel("message-reactions-\(matchId.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "message_reactions"
        )
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "message_reactions"
        )
        let deletions = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "message_reactions"
        )

        reactionInsertTask = Task { [weak self] in
            for await insert in inserts {
                guard let self else { return }
                guard self.realtimeStringValue(self.recordValue(insert.record, "match_id"))?.lowercased() == matchId.uuidString.lowercased() else {
                    continue
                }
                if let reaction = self.reaction(from: insert.record) {
                    self.appendOrReplace(reaction)
                }
            }
        }

        reactionUpdateTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                guard self.realtimeStringValue(self.recordValue(update.record, "match_id"))?.lowercased() == matchId.uuidString.lowercased() else {
                    continue
                }
                if let reaction = self.reaction(from: update.record) {
                    self.appendOrReplace(reaction)
                }
            }
        }

        reactionDeleteTask = Task { [weak self] in
            for await deletion in deletions {
                guard let self else { return }
                guard self.realtimeStringValue(self.recordValue(deletion.oldRecord, "match_id"))?.lowercased() == matchId.uuidString.lowercased() else {
                    continue
                }
                if let id = self.realtimeUUIDValue(self.recordValue(deletion.oldRecord, "id")) {
                    self.removeReaction(id: id, messageId: self.realtimeUUIDValue(self.recordValue(deletion.oldRecord, "message_id")))
                }
            }
        }

        do {
            try await channel.subscribeWithError()
            reactionChannel = channel
            subscribedReactionMatchId = matchId
        } catch {
            // ignore
        }
    }

    // MARK: - Typing Realtime
    func subscribeToTyping(matchId: UUID) async {
        if subscribedTypingMatchId == matchId, typingChannel != nil {
            return
        }

        typingListenerTask?.cancel()
        typingListenerTask = nil
        typingUpdateTask?.cancel()
        typingUpdateTask = nil
        typingExpiryTask?.cancel()
        typingExpiryTask = nil

        if let channel = typingChannel {
            await supabase.removeChannel(channel)
        }

        typingChannel = nil
        subscribedTypingMatchId = nil

        let channel = supabase.channel("typing-listener-\(matchId.uuidString)")

        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_typing"
        )

        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "chat_typing"
        )

        typingListenerTask = Task { [weak self] in
            for await event in inserts {
                guard let self else { return }
                self.handleTypingEvent(event.record, matchId: matchId)
            }
        }

        typingUpdateTask = Task { [weak self] in
            for await event in updates {
                guard let self else { return }
                self.handleTypingEvent(event.record, matchId: matchId)
            }
        }

        do {
            try await channel.subscribeWithError()
            typingChannel = channel
            subscribedTypingMatchId = matchId
        } catch {
            // ignore
        }
    }

    func unsubscribeMessages() {
        messageListenerTask?.cancel()
        messageListenerTask = nil

        messageUpdateTask?.cancel()
        messageUpdateTask = nil

        if let channel = messageChannel {
            Task {
                await self.supabase.removeChannel(channel)
            }
        }

        reactionInsertTask?.cancel()
        reactionInsertTask = nil
        reactionUpdateTask?.cancel()
        reactionUpdateTask = nil
        reactionDeleteTask?.cancel()
        reactionDeleteTask = nil

        if let channel = reactionChannel {
            Task {
                await self.supabase.removeChannel(channel)
            }
        }

        messageChannel = nil
        subscribedMessagesMatchId = nil
        reactionChannel = nil
        subscribedReactionMatchId = nil

        // Cleanup for typing channel
        typingListenerTask?.cancel()
        typingListenerTask = nil
        typingUpdateTask?.cancel()
        typingUpdateTask = nil
        typingExpiryTask?.cancel()
        typingExpiryTask = nil
        lastTypingSignalAt = nil
        isOtherUserTyping = false

        if let channel = typingChannel {
            Task { await self.supabase.removeChannel(channel) }
        }

        typingChannel = nil
        subscribedTypingMatchId = nil

        profileUpdateTask?.cancel()
        profileUpdateTask = nil

        if let channel = profileChannel {
            Task { await self.supabase.removeChannel(channel) }
        }

        profileChannel = nil
        subscribedProfileUserId = nil
        pendingMessageIds.removeAll()
        failedMessageIds.removeAll()
        failedMessageDrafts.removeAll()
    }

    private func realtimeStringValue(_ value: Any?) -> String? {
        guard let unwrapped = unwrapOptional(value) else { return nil }

        if unwrapped is NSNull {
            return nil
        }

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

        if isNullText(text) {
            return nil
        }

        return text
    }

    private func recordValue(_ record: [String: Any?], _ key: String) -> Any? {
        guard let value = record[key] else { return nil }
        return value
    }

    private func realtimeBoolValue(_ value: Any?) -> Bool? {
        guard let unwrapped = unwrapOptional(value) else { return nil }

        if unwrapped is NSNull {
            return nil
        }

        if let bool = unwrapped as? Bool {
            return bool
        }

        if let int = unwrapped as? Int {
            return int == 1
        }

        if let string = unwrapped as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes"].contains(normalized) {
                return true
            }
            if ["false", "0", "no"].contains(normalized) {
                return false
            }
        }

        return nil
    }

    private func realtimeUUIDValue(_ value: Any?) -> UUID? {
        guard let text = realtimeStringValue(value) else { return nil }
        return UUID(uuidString: text)
    }

    private func message(from record: [String: Any?]) -> Message? {
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

    private func reaction(from record: [String: Any?]) -> MessageReaction? {
        guard let idText = realtimeStringValue(recordValue(record, "id")),
              let id = UUID(uuidString: idText),
              let messageText = realtimeStringValue(recordValue(record, "message_id")),
              let messageId = UUID(uuidString: messageText),
              let userText = realtimeStringValue(recordValue(record, "user_id")),
              let userId = UUID(uuidString: userText),
              let emoji = realtimeStringValue(recordValue(record, "emoji")),
              let createdAt = realtimeStringValue(recordValue(record, "created_at")) else {
            return nil
        }

        return MessageReaction(id: id, messageId: messageId, userId: userId, emoji: emoji, createdAt: createdAt)
    }

    private func appendOrReplace(_ message: Message) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
            messages.sort(by: sortMessagesByCreatedAt)
        }
    }

    private func replaceWithServerMessages(_ serverMessages: [Message]) {
        let localOnlyMessages = messages.filter { message in
            pendingMessageIds.contains(message.id) || failedMessageIds.contains(message.id)
        }

        var merged = serverMessages
        for message in localOnlyMessages where !merged.contains(where: { $0.id == message.id }) {
            merged.append(message)
        }

        messages = merged.sorted(by: sortMessagesByCreatedAt)
    }

    private func sortMessagesByCreatedAt(_ first: Message, _ second: Message) -> Bool {
        guard let firstDate = parseDate(first.createdAt),
              let secondDate = parseDate(second.createdAt) else {
            return first.createdAt < second.createdAt
        }

        return firstDate < secondDate
    }

    private func appendOrReplace(_ reaction: MessageReaction) {
        var reactions = reactionsByMessageId[reaction.messageId] ?? []
        if let index = reactions.firstIndex(where: { $0.id == reaction.id || $0.userId == reaction.userId }) {
            reactions[index] = reaction
        } else {
            reactions.append(reaction)
        }

        reactionsByMessageId[reaction.messageId] = reactions.sorted { $0.createdAt < $1.createdAt }
    }

    private func removeReaction(id: UUID, messageId: UUID?) {
        if let messageId {
            reactionsByMessageId[messageId]?.removeAll { $0.id == id }
            return
        }

        for key in reactionsByMessageId.keys {
            reactionsByMessageId[key]?.removeAll { $0.id == id }
        }
    }

    // Helper to process typing events
    private func handleTypingEvent(_ record: [String: Any?], matchId: UUID) {
        guard let incomingMatchId = realtimeStringValue(recordValue(record, "match_id")),
              incomingMatchId.lowercased() == matchId.uuidString.lowercased() else {
            return
        }

        if let senderStr = realtimeStringValue(recordValue(record, "user_id")),
           let senderId = UUID(uuidString: senderStr),
           senderId == currentUserId {
            return
        }

        let isTyping = boolValue(from: recordValue(record, "is_typing"))

        if isTyping {
            lastTypingSignalAt = Date()
            isOtherUserTyping = true
            scheduleTypingExpiry()
        } else {
            typingExpiryTask?.cancel()
            typingExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                await MainActor.run {
                    self?.lastTypingSignalAt = nil
                    self?.isOtherUserTyping = false
                }
            }
        }
    }

    private func scheduleTypingExpiry() {
        typingExpiryTask?.cancel()

        typingExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))

            await MainActor.run {
                guard let self else { return }

                guard let lastTypingSignalAt = self.lastTypingSignalAt else {
                    self.isOtherUserTyping = false
                    return
                }

                if Date().timeIntervalSince(lastTypingSignalAt) >= 2.8 {
                    self.isOtherUserTyping = false
                    self.lastTypingSignalAt = nil
                }
            }
        }
    }

    private func boolValue(from value: Any?) -> Bool {
        guard let unwrapped = unwrapOptional(value) else { return false }

        if unwrapped is NSNull {
            return false
        }

        if let bool = unwrapped as? Bool {
            return bool
        }

        if let string = unwrapped as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "yes"
        }

        let text = String(describing: unwrapped)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return text == "true" || text == "1" || text == "yes"
    }

    private func isNullText(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

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

    // MARK: - Typing Indicator
    func startTyping(matchId: UUID, userId: UUID) async {
        struct Payload: Encodable {
            let match_id: UUID
            let user_id: UUID
            let is_typing: Bool
            let updated_at: String
        }

        do {
            try await supabase
                .from("chat_typing")
                .upsert(
                    Payload(
                        match_id: matchId,
                        user_id: userId,
                        is_typing: true,
                        updated_at: ISO8601DateFormatter().string(from: Date())
                    ),
                    onConflict: "match_id,user_id"
                )
                .execute()
        } catch {
            // error handling intentionally left blank
        }
    }

    func stopTyping(matchId: UUID, userId: UUID) async {
        struct Payload: Encodable {
            let match_id: UUID
            let user_id: UUID
            let is_typing: Bool
            let updated_at: String
        }

        do {
            try await supabase
                .from("chat_typing")
                .upsert(
                    Payload(
                        match_id: matchId,
                        user_id: userId,
                        is_typing: false,
                        updated_at: ISO8601DateFormatter().string(from: Date())
                    ),
                    onConflict: "match_id,user_id"
                )
                .execute()
        } catch {
            // error handling intentionally left blank
        }
    }

    // MARK: - Profile Realtime
    private func subscribeToProfileUpdates(userId: UUID) async {
        if subscribedProfileUserId == userId, profileChannel != nil {
            return
        }

        profileUpdateTask?.cancel()
        profileUpdateTask = nil

        if let channel = profileChannel {
            await supabase.removeChannel(channel)
        }

        profileChannel = nil
        subscribedProfileUserId = nil

        let channel = supabase.channel("profile-listener-\(userId.uuidString)")
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "profiles"
        )

        profileUpdateTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }

                guard let incomingProfileId = self.realtimeStringValue(self.recordValue(update.record, "id")),
                      incomingProfileId.lowercased() == userId.uuidString.lowercased() else {
                    continue
                }

                if let updated = try? await self.fetchProfile(userId: userId) {
                    await MainActor.run {
                        self.otherProfile = updated
                        self.isOtherUserPresent = self.isRecentlyOnline(updated)
                    }
                }
            }
        }

        do {
            try await channel.subscribeWithError()
            profileChannel = channel
            subscribedProfileUserId = userId
        } catch {
            // ignore
        }
    }
}

private extension Match {
    func includes(userId: UUID) -> Bool {
        userOneId == userId || userTwoId == userId
    }

    func otherUserId(for userId: UUID) -> UUID {
        userOneId == userId ? userTwoId : userOneId
    }
}




private let sharedISOFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
