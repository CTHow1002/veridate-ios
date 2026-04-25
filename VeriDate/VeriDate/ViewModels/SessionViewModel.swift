import Foundation
import Combine
import Supabase

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isCheckingSession = true
    @Published var isLoadingProfile = false
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
        isCheckingSession = true
        errorMessage = nil
        defer { isCheckingSession = false }

        do {
            let session = try await supabase.auth.session
            currentUserId = session.user.id
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            isAuthenticated = false
            currentUserId = nil
            currentProfile = nil
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil

        guard validate(email: email, password: password) else { return }

        do {
            let response = try await supabase.auth.signUp(email: email, password: password)

            guard let session = response.session else {
                isAuthenticated = false
                currentUserId = nil
                currentProfile = nil
                errorMessage = "Account created. Please confirm your email, then sign in."
                return
            }

            currentUserId = session.user.id
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Could not create your account.")
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil

        guard validate(email: email, password: password) else { return }

        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUserId = session.user.id
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Could not sign you in.")
        }
    }

    func signOut() async {
        errorMessage = nil

        do {
            try await supabase.auth.signOut()
            isAuthenticated = false
            currentUserId = nil
            currentProfile = nil
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Could not sign out.")
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
                .upsert(
                    InsertProfile(id: userId, verification_status: VerificationStatus.unsubmitted.rawValue),
                    onConflict: "id",
                    ignoreDuplicates: true
                )
                .execute()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Signed in, but could not prepare your profile.")
        }
    }

    func loadProfile() async {
        guard let userId = currentUserId else {
            currentProfile = nil
            isLoadingProfile = false
            return
        }

        isLoadingProfile = true
        errorMessage = nil
        defer { isLoadingProfile = false }

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
            currentProfile = nil
            errorMessage = userFacingMessage(for: error, fallback: "Could not load your profile.")
        }
    }

    func markVerificationPending() async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = "Please sign in again before submitting verification."
            return false
        }

        struct UpdateVerificationStatus: Encodable {
            let verification_status: String
        }

        do {
            try await supabase
                .from("profiles")
                .update(UpdateVerificationStatus(verification_status: VerificationStatus.pending.rawValue))
                .eq("id", value: userId)
                .execute()

            await loadProfile()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: "Uploaded your files, but could not submit verification.")
            return false
        }
    }

    private func validate(email: String, password: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty || password.isEmpty {
            errorMessage = "Enter both email and password."
            return false
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters."
            return false
        }

        return true
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        let message = error.localizedDescription

        if message.localizedCaseInsensitiveContains("Invalid login credentials") {
            return "Email or password is incorrect."
        }

        if message.localizedCaseInsensitiveContains("Email not confirmed") {
            return "Please confirm your email before signing in."
        }

        if message.localizedCaseInsensitiveContains("already registered") {
            return "This email already has an account. Try signing in."
        }

        if message.localizedCaseInsensitiveContains("network") {
            return "Network problem. Check your connection and try again."
        }

        return message.isEmpty ? fallback : "\(fallback) \(message)"
    }
}
