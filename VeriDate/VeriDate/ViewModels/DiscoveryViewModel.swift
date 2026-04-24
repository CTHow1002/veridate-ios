import Foundation
import Combine
import Supabase
import PostgREST

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func loadProfiles(userId: UUID) async {
        do {
            let response: [Profile] = try await supabase
                .rpc("get_discovery_profiles", params: ["requesting_user_id": userId.uuidString])
                .execute()
                .value

            profiles = response
        } catch {
            errorMessage = error.localizedDescription
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
