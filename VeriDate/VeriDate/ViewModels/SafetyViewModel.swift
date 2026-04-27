import Combine
import Foundation
import Supabase

enum SafetyReportReason: String, CaseIterable, Identifiable {
    case inappropriateBehavior = "Inappropriate behavior"
    case harassment = "Harassment"
    case fakeProfile = "Fake profile"
    case scam = "Scam or suspicious activity"
    case underage = "Underage user"
    case other = "Other"

    var id: String { rawValue }
}

@MainActor
final class SafetyViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let supabase = SupabaseManager.shared.client

    func submitReport(
        reporterUserId: UUID,
        reportedUserId: UUID,
        matchId: UUID?,
        reason: SafetyReportReason,
        details: String
    ) async -> Bool {
        struct ReportPayload: Encodable {
            let reporter_user_id: UUID
            let reported_user_id: UUID
            let match_id: UUID?
            let reason: String
            let details: String?
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            try await supabase
                .from("reports")
                .insert(
                    ReportPayload(
                        reporter_user_id: reporterUserId,
                        reported_user_id: reportedUserId,
                        match_id: matchId,
                        reason: reason.rawValue,
                        details: trimmedOrNil(details)
                    )
                )
                .execute()

            successMessage = "Report submitted. Thank you for helping keep VeriDate safe."
            return true
        } catch {
            errorMessage = "Could not submit report. \(error.localizedDescription)"
            return false
        }
    }

    func blockUser(
        blockerUserId: UUID,
        blockedUserId: UUID,
        matchId: UUID?,
        reason: String? = nil
    ) async -> Bool {
        struct BlockPayload: Encodable {
            let blocker_user_id: UUID
            let blocked_user_id: UUID
            let match_id: UUID?
            let reason: String?
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            try await supabase
                .from("blocks")
                .upsert(
                    BlockPayload(
                        blocker_user_id: blockerUserId,
                        blocked_user_id: blockedUserId,
                        match_id: matchId,
                        reason: trimmedOrNil(reason)
                    ),
                    onConflict: "blocker_user_id,blocked_user_id"
                )
                .execute()

            successMessage = "User blocked."
            return true
        } catch {
            errorMessage = "Could not block this user. \(error.localizedDescription)"
            return false
        }
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
