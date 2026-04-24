import Foundation
import Combine
import Supabase
import PostgREST

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUserId: UUID?
    @Published var currentProfile: Profile?
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    init() {
        Task {
            await refreshSession()
        }
    }

    func refreshSession() async {
        do {
            let session = try await supabase.auth.session
            currentUserId = session.user.id
            isAuthenticated = true
            await loadProfile()
        } catch {
            isAuthenticated = false
            currentUserId = nil
        }
    }

    func signUp(email: String, password: String) async {
        do {
            let response = try await supabase.auth.signUp(email: email, password: password)
            currentUserId = response.user.id
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUserId = session.user.id
            isAuthenticated = true
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
            isAuthenticated = false
            currentUserId = nil
            currentProfile = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createEmptyProfileIfNeeded() async {
        guard let userId = currentUserId else { return }

        struct InsertProfile: Encodable {
            let id: UUID
            let verification_status: String
        }

        do {
            try await supabase
                .from("profiles")
                .upsert(InsertProfile(id: userId, verification_status: "unsubmitted"))
                .execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadProfile() async {
        guard let userId = currentUserId else { return }

        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            currentProfile = profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
