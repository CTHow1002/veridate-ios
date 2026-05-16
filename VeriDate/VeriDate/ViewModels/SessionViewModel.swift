import Foundation
import Combine
import CoreLocation
import Supabase

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isCheckingSession = true
    @Published var isLoadingProfile = false
    @Published var currentUserId: UUID?
    @Published var currentUserEmail: String?
    @Published var currentProfile: Profile?
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client
    private var cancellables = Set<AnyCancellable>()

    init() {
        observePushToken()
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

            if session.isExpired {
                do {
                    let refreshedSession = try await supabase.auth.refreshSession()
                    currentUserId = refreshedSession.user.id
                    currentUserEmail = refreshedSession.user.email
                    isAuthenticated = true
                } catch {
                    isAuthenticated = false
                    currentUserId = nil
                    currentUserEmail = nil
                    currentProfile = nil
                    return
                }
            } else {
                currentUserId = session.user.id
                currentUserEmail = session.user.email
                isAuthenticated = true
            }

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
                currentUserEmail = nil
                currentProfile = nil
                errorMessage = AppLanguageManager.localized("session.auth.accountCreatedConfirmEmail")
                return
            }

            currentUserId = session.user.id
            currentUserEmail = session.user.email
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.auth.error.createAccount"))
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil

        guard validate(email: email, password: password) else { return }

        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUserId = session.user.id
            currentUserEmail = session.user.email
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.auth.error.signIn"))
        }
    }

    func signInOrCreateRoughLoginAccount(identifier: String, source: String) async -> Bool {
        errorMessage = nil

        let normalizedIdentifier = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedIdentifier.isEmpty else {
            errorMessage = AppLanguageManager.localized("session.auth.error.enterPhone")
            return false
        }

        let email = roughLoginEmail(identifier: normalizedIdentifier, source: source)
        let password = roughLoginPassword(identifier: normalizedIdentifier, source: source)

        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUserId = session.user.id
            currentUserEmail = session.user.email
            isAuthenticated = true
            await createEmptyProfileIfNeeded()
            await loadProfile()
            return true
        } catch {
            do {
                let response = try await supabase.auth.signUp(email: email, password: password)

                guard let session = response.session else {
                    errorMessage = AppLanguageManager.localized("session.auth.error.demoRequiresEmailConfirmation")
                    return false
                }

                currentUserId = session.user.id
                currentUserEmail = session.user.email
                isAuthenticated = true
                await createEmptyProfileIfNeeded()
                await loadProfile()
                return true
            } catch {
                errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.auth.error.loginMethod"))
                return false
            }
        }
    }

    func signOut() async {
        errorMessage = nil

        do {
            await updatePresence(isOnline: false)
            try await supabase.auth.signOut()
            isAuthenticated = false
            currentUserId = nil
            currentUserEmail = nil
            currentProfile = nil
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.auth.error.signOut"))
        }
    }

    func updateAccountEmail(_ email: String) async -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidEmail(trimmedEmail) else {
            errorMessage = AppLanguageManager.localized("session.account.error.validEmail")
            return false
        }

        do {
            let user = try await supabase.auth.update(user: UserAttributes(email: trimmedEmail))
            currentUserEmail = user.email ?? user.newEmail ?? trimmedEmail
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.account.error.updateEmail"))
            return false
        }
    }

    func updateAccountPassword(_ password: String) async -> Bool {
        guard password.count >= 8 else {
            errorMessage = AppLanguageManager.localized("session.account.error.passwordMin8")
            return false
        }

        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: password))
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.account.error.updatePassword"))
            return false
        }
    }

    func requestAccountDeletion() async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = AppLanguageManager.localized("session.accountDeletion.error.signInAgainRequest")
            return false
        }

        let requestedDate = Date()
        let scheduledDate = requestedDate.addingTimeInterval(24 * 60 * 60)
        let requestedAt = isoString(from: requestedDate)
        let scheduledAt = isoString(from: scheduledDate)

        struct AccountDeletionRequestRow: Decodable {
            let id: UUID
            let scheduled_delete_at: String?
        }

        struct InsertAccountDeletionRequest: Encodable {
            let user_id: UUID
            let status: String
            let requested_at: String
            let scheduled_delete_at: String
        }

        struct DeactivateProfile: Encodable {
            let is_deactivated: Bool
            let account_deletion_requested_at: String
            let account_deletion_scheduled_at: String
            let is_online: Bool
        }

        do {
            let existingRequests: [AccountDeletionRequestRow] = try await supabase
                .from("account_deletion_requests")
                .select("id, scheduled_delete_at")
                .eq("user_id", value: userId)
                .eq("status", value: "pending")
                .limit(1)
                .execute()
                .value

            if existingRequests.isEmpty {
                try await supabase
                    .from("account_deletion_requests")
                    .insert(InsertAccountDeletionRequest(
                        user_id: userId,
                        status: "pending",
                        requested_at: requestedAt,
                        scheduled_delete_at: scheduledAt
                    ))
                    .execute()
            }

            try await supabase
                .from("profiles")
                .update(DeactivateProfile(
                    is_deactivated: true,
                    account_deletion_requested_at: requestedAt,
                    account_deletion_scheduled_at: existingRequests.first?.scheduled_delete_at ?? scheduledAt,
                    is_online: false
                ))
                .eq("id", value: userId)
                .execute()

            await loadProfile()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.accountDeletion.error.request"))
            return false
        }
    }

    func cancelAccountDeletion() async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = AppLanguageManager.localized("session.accountDeletion.error.signInAgainCancel")
            return false
        }

        struct CancelDeletionRequest: Encodable {
            let status: String
            let canceled_at: String
        }

        struct ReactivateProfile: Encodable {
            let is_deactivated: Bool

            enum CodingKeys: String, CodingKey {
                case is_deactivated
                case account_deletion_requested_at
                case account_deletion_scheduled_at
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(is_deactivated, forKey: .is_deactivated)
                try container.encodeNil(forKey: .account_deletion_requested_at)
                try container.encodeNil(forKey: .account_deletion_scheduled_at)
            }
        }

        do {
            try await supabase
                .from("account_deletion_requests")
                .update(CancelDeletionRequest(status: "canceled", canceled_at: isoString(from: Date())))
                .eq("user_id", value: userId)
                .eq("status", value: "pending")
                .execute()

            try await supabase
                .from("profiles")
                .update(ReactivateProfile(is_deactivated: false))
                .eq("id", value: userId)
                .execute()

            await loadProfile()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.accountDeletion.error.cancel"))
            return false
        }
    }

    func createEmptyProfileIfNeeded() async {
        guard let userId = currentUserId else { return }

        struct InsertProfile: Encodable {
            let id: UUID
            let verification_status: String
            let gender_interest: String
            let marital_status: String
        }

        do {
            try await supabase
                .from("profiles")
                .upsert(
                    InsertProfile(
                        id: userId,
                        verification_status: VerificationStatus.unsubmitted.rawValue,
                        gender_interest: GenderInterest.opposite_gender.rawValue,
                        marital_status: MaritalStatus.single.rawValue
                    ),
                    onConflict: "id",
                    ignoreDuplicates: true
                )
                .execute()
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.profile.error.prepareProfile"))
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
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.profile.error.loadProfile"))
        }
    }

    func markVerificationPending() async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = AppLanguageManager.localized("session.verification.error.signInAgainSubmit")
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
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.verification.error.submit"))
            return false
        }
    }

    func updateProfileLocation(_ coordinate: CLLocationCoordinate2D) async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = AppLanguageManager.localized("session.location.error.signInAgainUpdate")
            return false
        }

        struct UpdateLocation: Encodable {
            let latitude: Double
            let longitude: Double
        }

        do {
            try await supabase
                .from("profiles")
                .update(UpdateLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                .eq("id", value: userId)
                .execute()

            await loadProfile()
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.location.error.update"))
            return false
        }
    }

    func updateDiscoveryVisibility(isDiscoverable: Bool) async -> Bool {
        guard let userId = currentUserId else {
            errorMessage = AppLanguageManager.localized("session.visibility.error.signInAgainChange")
            return false
        }

        struct UpdateDiscoveryVisibility: Encodable {
            let is_discoverable: Bool
        }

        do {
            try await supabase
                .from("profiles")
                .update(UpdateDiscoveryVisibility(is_discoverable: isDiscoverable))
                .eq("id", value: userId)
                .execute()

            currentProfile?.isDiscoverable = isDiscoverable
            return true
        } catch {
            errorMessage = userFacingMessage(for: error, fallback: AppLanguageManager.localized("session.visibility.error.update"))
            return false
        }
    }

    func keepPresenceUpdated() async {
        while !Task.isCancelled, isAuthenticated {
            await updatePresence(isOnline: true)
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func updatePresence(isOnline: Bool, reportErrors: Bool = true) async {
        guard let userId = currentUserId else { return }
        let shouldShowOnlineStatus = UserDefaults.standard.object(forKey: PrivacyPreferenceKey.showOnlineStatus) as? Bool ?? true
        let visibleOnlineState = isOnline && shouldShowOnlineStatus

        struct PresenceParams: Encodable {
            let p_is_online: Bool
        }

        do {
            try await supabase
                .rpc("set_user_presence", params: PresenceParams(p_is_online: visibleOnlineState))
                .execute()

            if currentProfile?.id == userId {
                currentProfile?.isOnline = visibleOnlineState
                currentProfile?.lastSeenAt = ISO8601DateFormatter().string(from: Date())
            }
        } catch {
            if reportErrors {
                errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("session.presence.error.updateFormat"), error.localizedDescription)
            }
        }
    }

    private func validate(email: String, password: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty || password.isEmpty {
            errorMessage = AppLanguageManager.localized("session.auth.error.emailPasswordRequired")
            return false
        }

        if password.count < 6 {
            errorMessage = AppLanguageManager.localized("session.auth.error.passwordMin6")
            return false
        }

        return true
    }

    private func roughLoginEmail(identifier: String, source: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let cleanedIdentifier = identifier
            .components(separatedBy: allowed.inverted)
            .joined()
        let cleanedSource = source
            .components(separatedBy: allowed.inverted)
            .joined()
            .lowercased()
        let safeIdentifier = cleanedIdentifier.isEmpty ? UUID().uuidString.replacingOccurrences(of: "-", with: "") : cleanedIdentifier

        return "\(cleanedSource)-\(safeIdentifier)@rough-login.veridate.app"
    }

    private func roughLoginPassword(identifier: String, source: String) -> String {
        "VeriDateRough-\(source)-\(identifier)-2026!"
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && !email.contains(" ")
    }

    private func isoString(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        let message = error.localizedDescription

        if message.localizedCaseInsensitiveContains("Invalid login credentials") {
            return AppLanguageManager.localized("session.auth.error.invalidCredentials")
        }

        if message.localizedCaseInsensitiveContains("Email not confirmed") {
            return AppLanguageManager.localized("session.auth.error.emailNotConfirmed")
        }

        if message.localizedCaseInsensitiveContains("already registered") {
            return AppLanguageManager.localized("session.auth.error.emailAlreadyRegistered")
        }

        if message.localizedCaseInsensitiveContains("network") {
            return AppLanguageManager.localized("session.error.network")
        }

        return message.isEmpty ? fallback : String.localizedStringWithFormat(AppLanguageManager.localized("session.error.fallbackWithDetailFormat"), fallback, message)
    }

    private func observePushToken() {
        NotificationCenter.default.publisher(for: Notification.Name("DidReceivePushToken"))
            .compactMap { $0.object as? String }
            .sink { [weak self] token in
                Task {
                    await self?.savePushToken(token)
                }
            }
            .store(in: &cancellables)
    }

    private func savePushToken(_ token: String) async {
        guard let userId = currentUserId else { return }
        guard UserDefaults.standard.bool(forKey: NotificationPreferenceKey.pushEnabled) else { return }

        struct PushToken: Encodable {
            let user_id: UUID
            let token: String
            let platform: String
        }

        do {
            try await supabase
                .from("user_push_tokens")
                .upsert(
                    PushToken(user_id: userId, token: token, platform: "ios"),
                    onConflict: "user_id,token"
                )
                .execute()
        } catch {
            print("Failed to save push token:", error.localizedDescription)
        }
    }
}
