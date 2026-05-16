import Foundation
import PostgREST
import Supabase

final class ProfileInterestService {
    static let shared = ProfileInterestService()
    private let supabase = SupabaseManager.shared.client

    private init() {}

    func loadProfileInterests(userId: UUID) async throws -> [String] {
        let rows: [ProfileInterest] = try await supabase
            .from("profile_interests")
            .select()
            .eq("user_id", value: userId)
            .order("interest", ascending: true)
            .execute()
            .value

        return rows.map(\.interest)
    }

    func saveProfileInterests(userId: UUID, interests: [String]) async throws {
        struct InsertInterest: Encodable {
            let user_id: UUID
            let interest: String
        }

        try await supabase
            .from("profile_interests")
            .delete()
            .eq("user_id", value: userId)
            .execute()

        let cleanedInterests = interests
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
            .prefix(5)

        let payloads = cleanedInterests.map { interest in
            InsertInterest(user_id: userId, interest: interest)
        }

        guard !payloads.isEmpty else { return }

        try await supabase
            .from("profile_interests")
            .insert(payloads)
            .execute()
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

