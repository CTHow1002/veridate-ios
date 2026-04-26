import Combine
import Foundation
import Supabase

struct MatchRow: Identifiable, Hashable {
    let match: Match
    let profile: Profile
    let lastMessage: Message?

    var id: UUID {
        match.id
    }

    func otherUserId(for currentUserId: UUID) -> UUID {
        match.userOneId == currentUserId ? match.userTwoId : match.userOneId
    }
}

@MainActor
final class MatchesViewModel: ObservableObject {
    @Published var matches: [MatchRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func loadMatches(userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.verificationStatus == .verified else {
            matches = []
            errorMessage = "Only verified users can view matches."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [Match] = try await supabase
                .from("matches")
                .select()
                .or("user_one_id.eq.\(userId.uuidString),user_two_id.eq.\(userId.uuidString)")
                .order("created_at", ascending: false)
                .execute()
                .value

            var loaded: [MatchRow] = []
            for match in rows {
                let otherUserId = match.userOneId == userId ? match.userTwoId : match.userOneId
                if let profile = try await loadProfile(userId: otherUserId) {
                    loaded.append(MatchRow(match: match, profile: profile, lastMessage: try await loadLastMessage(matchId: match.id)))
                }
            }

            matches = loaded
        } catch {
            errorMessage = "Could not load matches. \(error.localizedDescription)"
        }
    }

    private func loadProfile(userId: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        return profiles.first
    }

    private func loadLastMessage(matchId: UUID) async throws -> Message? {
        let messages: [Message] = try await supabase
            .from("messages")
            .select()
            .eq("match_id", value: matchId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return messages.first
    }
}
