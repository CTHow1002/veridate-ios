import Foundation
import Combine
import Supabase
import PostgREST

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isSavingFilters = false
    @Published var actingProfileIds: Set<UUID> = []

    @Published var preferredGender: GenderType?
    @Published var minAge = 18
    @Published var maxAge = 50
    @Published var preferredCity = ""
    @Published var minDistanceKm = 0
    @Published var maxDistanceKm = 100
    @Published var minHeightCm = 120
    @Published var maxHeightCm = 200
    @Published var educationLevel = ""
    @Published var relationshipGoal: RelationshipIntention?

    private let supabase = SupabaseManager.shared.client

    func loadProfiles(userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.verificationStatus == .verified else {
            profiles = []
            errorMessage = "Only verified users can use Discover."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [Profile] = try await supabase
                .rpc("get_discovery_profiles", params: ["requesting_user_id": userId.uuidString])
                .execute()
                .value

            profiles = response
        } catch {
            errorMessage = "Could not load discovery profiles. \(error.localizedDescription)"
        }
    }

    func loadFilters(userId: UUID) async {
        struct FilterRow: Decodable {
            let preferred_gender: GenderType?
            let min_age: Int?
            let max_age: Int?
            let preferred_city: String?
            let min_distance_km: Int?
            let max_distance_km: Int?
            let min_height_cm: Int?
            let max_height_cm: Int?
            let education_level: String?
            let relationship_goal: RelationshipIntention?
        }

        do {
            let filters: [FilterRow] = try await supabase
                .from("dating_filters")
                .select("preferred_gender,min_age,max_age,preferred_city,min_distance_km,max_distance_km,min_height_cm,max_height_cm,education_level,relationship_goal")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            guard let filter = filters.first else { return }
            preferredGender = filter.preferred_gender
            minAge = filter.min_age ?? minAge
            maxAge = filter.max_age ?? maxAge
            preferredCity = filter.preferred_city ?? ""
            minDistanceKm = filter.min_distance_km ?? minDistanceKm
            maxDistanceKm = filter.max_distance_km ?? maxDistanceKm
            minHeightCm = filter.min_height_cm ?? minHeightCm
            maxHeightCm = filter.max_height_cm ?? maxHeightCm
            educationLevel = filter.education_level ?? ""
            relationshipGoal = filter.relationship_goal
        } catch {
            errorMessage = "Could not load filters. \(error.localizedDescription)"
        }
    }

    func saveFilters(userId: UUID) async -> Bool {
        struct FilterPayload: Encodable {
            let user_id: UUID
            let preferred_gender: String?
            let min_age: Int
            let max_age: Int
            let preferred_city: String?
            let min_distance_km: Int
            let max_distance_km: Int
            let min_height_cm: Int?
            let max_height_cm: Int?
            let education_level: String?
            let relationship_goal: String?
            let verified_only: Bool
        }

        isSavingFilters = true
        errorMessage = nil
        defer { isSavingFilters = false }

        do {
            try await supabase
                .from("dating_filters")
                .upsert(
                    FilterPayload(
                        user_id: userId,
                        preferred_gender: preferredGender?.rawValue,
                        min_age: min(minAge, maxAge),
                        max_age: max(minAge, maxAge),
                        preferred_city: trimmedOrNil(preferredCity),
                        min_distance_km: min(minDistanceKm, maxDistanceKm),
                        max_distance_km: max(minDistanceKm, maxDistanceKm),
                        min_height_cm: min(minHeightCm, maxHeightCm),
                        max_height_cm: max(minHeightCm, maxHeightCm),
                        education_level: trimmedOrNil(educationLevel),
                        relationship_goal: relationshipGoal?.rawValue,
                        verified_only: true
                    ),
                    onConflict: "user_id"
                )
                .execute()

            return true
        } catch {
            errorMessage = "Could not save filters. \(error.localizedDescription)"
            return false
        }
    }

    func like(userId: UUID, targetUserId: UUID) async {
        await action(userId: userId, targetUserId: targetUserId, action: "like")
    }

    func pass(userId: UUID, targetUserId: UUID) async {
        await action(userId: userId, targetUserId: targetUserId, action: "pass")
    }

    private func action(userId: UUID, targetUserId: UUID, action: String) async {
        struct ActionPayload: Encodable {
            let actor_user_id: UUID
            let target_user_id: UUID
            let action: String
        }

        actingProfileIds.insert(targetUserId)
        errorMessage = nil
        defer { actingProfileIds.remove(targetUserId) }

        do {
            try await supabase
                .from("profile_actions")
                .insert(ActionPayload(actor_user_id: userId, target_user_id: targetUserId, action: action))
                .execute()

            profiles.removeAll { $0.id == targetUserId }
        } catch {
            errorMessage = "Could not save your \(action). \(error.localizedDescription)"
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
