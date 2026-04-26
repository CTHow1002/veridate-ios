import Combine
import Foundation
import Supabase

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?

    private let supabase = SupabaseManager.shared.client

    func loadMessages(match: Match, userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.verificationStatus == .verified else {
            messages = []
            errorMessage = "Only verified users can message matches."
            return
        }

        guard match.includes(userId: userId) else {
            messages = []
            errorMessage = "You can only message someone after you have matched."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await fetchMessages(matchId: match.id)
            await markMessagesRead(matchId: match.id, userId: userId)
        } catch {
            errorMessage = "Could not load messages. \(error.localizedDescription)"
        }
    }

    func refreshMessages(match: Match, userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.verificationStatus == .verified, match.includes(userId: userId) else {
            return
        }

        do {
            let latestMessages = try await fetchMessages(matchId: match.id)
            guard latestMessages != messages else { return }

            messages = latestMessages
            await markMessagesRead(matchId: match.id, userId: userId)
        } catch {
            if messages.isEmpty {
                errorMessage = "Could not refresh messages. \(error.localizedDescription)"
            }
        }
    }

    func sendMessage(body: String, match: Match, userId: UUID, currentProfile: Profile?) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard currentProfile?.verificationStatus == .verified else {
            errorMessage = "Only verified users can send messages."
            return false
        }

        guard match.includes(userId: userId) else {
            errorMessage = "You can only message someone after you have matched."
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = "Type a message before sending."
            return false
        }

        struct NewMessage: Encodable {
            let match_id: UUID
            let sender_id: UUID
            let body: String
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let inserted: [Message] = try await supabase
                .from("messages")
                .insert(NewMessage(match_id: match.id, sender_id: userId, body: trimmedBody))
                .select()
                .execute()
                .value

            if let message = inserted.first {
                messages.append(message)
            } else {
                await loadMessages(match: match, userId: userId, currentProfile: currentProfile)
            }

            return true
        } catch {
            errorMessage = "Could not send message. \(error.localizedDescription)"
            return false
        }
    }

    func blockUser(match: Match, blockedUserId: UUID, userId: UUID, reason: String?) async {
        guard match.includes(userId: userId), match.includes(userId: blockedUserId) else {
            errorMessage = "You can only block users you have matched with."
            return
        }

        struct BlockPayload: Encodable {
            let blocker_user_id: UUID
            let blocked_user_id: UUID
            let match_id: UUID
            let reason: String?
        }

        do {
            try await supabase
                .from("user_blocks")
                .upsert(
                    BlockPayload(
                        blocker_user_id: userId,
                        blocked_user_id: blockedUserId,
                        match_id: match.id,
                        reason: clean(reason)
                    ),
                    onConflict: "blocker_user_id,blocked_user_id"
                )
                .execute()

            actionMessage = "User blocked."
        } catch {
            errorMessage = "Could not block this user. \(error.localizedDescription)"
        }
    }

    func reportUser(match: Match, reportedUserId: UUID, userId: UUID, reason: String) async {
        guard match.includes(userId: userId), match.includes(userId: reportedUserId) else {
            errorMessage = "You can only report users you have matched with."
            return
        }

        guard let reason = clean(reason) else {
            errorMessage = "Add a short reason before reporting."
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
                .from("user_reports")
                .insert(ReportPayload(reporter_user_id: userId, reported_user_id: reportedUserId, match_id: match.id, reason: reason))
                .execute()

            actionMessage = "Report submitted."
        } catch {
            errorMessage = "Could not submit report. \(error.localizedDescription)"
        }
    }

    private func markMessagesRead(matchId: UUID, userId: UUID) async {
        struct ReadPayload: Encodable {
            let is_read: Bool
        }

        do {
            try await supabase
                .from("messages")
                .update(ReadPayload(is_read: true))
                .eq("match_id", value: matchId)
                .neq("sender_id", value: userId)
                .execute()
        } catch {
            errorMessage = "Messages loaded, but could not mark them as read."
        }
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

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Match {
    func includes(userId: UUID) -> Bool {
        userOneId == userId || userTwoId == userId
    }
}
