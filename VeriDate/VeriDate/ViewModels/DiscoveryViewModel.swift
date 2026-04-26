import Foundation
import Combine
import Supabase
import PostgREST

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var errorMessage: String?
    @Published var maxDistanceKm = 50
    @Published var isSavingFilters = false

    private let supabase = SupabaseManager.shared.client

    func loadProfiles(userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.latitude != nil, currentProfile?.longitude != nil else {
            profiles = []
            errorMessage = "Add your location in your profile to see nearby matches."
            return
        }

        do {
            errorMessage = nil
            let response: [Profile] = try await supabase
                .rpc("get_discovery_profiles", params: ["requesting_user_id": userId.uuidString])
                .execute()
                .value

            profiles = response
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadFilters(userId: UUID) async {
        struct FilterRow: Decodable {
            let max_distance_km: Int?
        }

        do {
            let filters: [FilterRow] = try await supabase
                .from("dating_filters")
                .select("max_distance_km")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            maxDistanceKm = filters.first?.max_distance_km ?? maxDistanceKm
        } catch {
            errorMessage = "Could not load filters. \(error.localizedDescription)"
        }
    }

    func saveFilters(userId: UUID) async -> Bool {
        struct FilterPayload: Encodable {
            let user_id: UUID
            let min_age: Int
            let max_age: Int
            let max_distance_km: Int
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
                        min_age: 18,
                        max_age: 100,
                        max_distance_km: maxDistanceKm,
                        verified_only: false
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

        do {
            try await supabase
                .from("profile_actions")
                .insert(ActionPayload(actor_user_id: userId, target_user_id: targetUserId, action: action))
                .execute()

            profiles.removeAll { $0.id == targetUserId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
