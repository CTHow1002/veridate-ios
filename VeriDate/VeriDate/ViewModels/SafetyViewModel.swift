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

    var localizedTitle: String {
        switch self {
        case .inappropriateBehavior:
            return AppLanguageManager.localized("safety.report.reason.inappropriateBehavior")
        case .harassment:
            return AppLanguageManager.localized("safety.report.reason.harassment")
        case .fakeProfile:
            return AppLanguageManager.localized("safety.report.reason.fakeProfile")
        case .scam:
            return AppLanguageManager.localized("safety.report.reason.scam")
        case .underage:
            return AppLanguageManager.localized("safety.report.reason.underage")
        case .other:
            return AppLanguageManager.localized("safety.report.reason.other")
        }
    }
}

struct SafetyBlockedUser: Identifiable, Hashable {
    let id: UUID
    let blockedUserId: UUID
    let profile: Profile
    let reason: String?
    let createdAt: String?
}

@MainActor
final class SafetyViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var isLoadingBlockedUsers = false
    @Published var blockedUsers: [SafetyBlockedUser] = []
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let supabase = SupabaseManager.shared.client

    private struct BlockListRow: Decodable {
        let id: UUID
        let blockedUserId: UUID
        let reason: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case blockedUserId = "blocked_user_id"
            case reason
            case createdAt = "created_at"
        }
    }

    private struct LegacyBlockListRow: Decodable {
        let id: UUID
        let blockedUserId: UUID
        let reason: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case blockedUserId = "blocked_id"
            case reason
            case createdAt = "created_at"
        }
    }

    private struct EmptyPayload: Encodable {}

    func submitReport(
        reporterUserId: UUID,
        reportedUserId: UUID,
        matchId: UUID?,
        reason: SafetyReportReason,
        details: String,
        proof: ReportProofAttachment?
    ) async -> Bool {
        struct ReportPayload: Encodable {
            let reporter_user_id: UUID
            let reported_user_id: UUID
            let match_id: UUID?
            let reason: String
            let details: String?
            let proof_file_path: String?
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            let proofPath = try await uploadProofIfNeeded(proof, reporterUserId: reporterUserId)

            try await supabase
                .from("reports")
                .insert(
                    ReportPayload(
                        reporter_user_id: reporterUserId,
                        reported_user_id: reportedUserId,
                        match_id: matchId,
                        reason: reason.rawValue,
                        details: trimmedOrNil(details),
                        proof_file_path: proofPath
                    )
                )
                .execute()

            successMessage = AppLanguageManager.localized("safety.report.submitted")
            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(
                AppLanguageManager.localized("safety.report.submitFailedFormat"),
                error.localizedDescription
            )
            return false
        }
    }

    private func uploadProofIfNeeded(_ proof: ReportProofAttachment?, reporterUserId: UUID) async throws -> String? {
        guard let proof else { return nil }

        let safeName = cleanFileName(proof.fileName, fallback: "report-proof.jpg")
        let path = "reports/\(reporterUserId.uuidString)/\(UUID().uuidString)-\(safeName)"

        try await supabase.storage
            .from("verification-documents")
            .upload(
                path,
                data: proof.data,
                options: FileOptions(contentType: proof.contentType, upsert: true)
            )

        return path
    }

    private func cleanFileName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        return cleaned.isEmpty ? fallback : cleaned
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

        struct MinimalBlockPayload: Encodable {
            let blocker_user_id: UUID
            let blocked_user_id: UUID
        }

        struct LegacyBlockPayload: Encodable {
            let blocker_id: UUID
            let blocked_id: UUID
            let match_id: UUID?
            let reason: String?
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            let payload = BlockPayload(
                blocker_user_id: blockerUserId,
                blocked_user_id: blockedUserId,
                match_id: matchId,
                reason: trimmedOrNil(reason)
            )
            let minimalPayload = MinimalBlockPayload(
                blocker_user_id: blockerUserId,
                blocked_user_id: blockedUserId
            )
            let legacyPayload = LegacyBlockPayload(
                blocker_id: blockerUserId,
                blocked_id: blockedUserId,
                match_id: matchId,
                reason: trimmedOrNil(reason)
            )

            try await saveBlock(payload: payload, fallbackPayload: minimalPayload, legacyPayload: legacyPayload, table: "blocks")
            try? await saveBlock(payload: payload, fallbackPayload: minimalPayload, table: "user_blocks")
            guard await hasBlockInAnyTable(blockerUserId: blockerUserId, blockedUserId: blockedUserId) else {
                throw SafetyError.blockDidNotPersist
            }

            successMessage = AppLanguageManager.localized("chat_action_user_blocked")
            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(
                AppLanguageManager.localized("chat_error_block_user_format"),
                error.localizedDescription
            )
            return false
        }
    }

    func loadBlockedUsers(blockerUserId: UUID) async {
        isLoadingBlockedUsers = true
        errorMessage = nil
        defer { isLoadingBlockedUsers = false }

        do {
            var blocks = try await loadBlockRows(table: "blocks", blockerUserId: blockerUserId)
            let oldBlocks = (try? await loadLegacyBlockRows(table: "blocks", blockerUserId: blockerUserId)) ?? []
            let legacyBlocks = (try? await loadBlockRows(table: "user_blocks", blockerUserId: blockerUserId)) ?? []
            let knownBlockedIds = Set(blocks.map(\.blockedUserId))
            blocks.append(contentsOf: oldBlocks.filter { !knownBlockedIds.contains($0.blockedUserId) })
            let refreshedBlockedIds = Set(blocks.map(\.blockedUserId))
            blocks.append(contentsOf: legacyBlocks.filter { !refreshedBlockedIds.contains($0.blockedUserId) })

            var loadedUsers: [SafetyBlockedUser] = []
            for block in blocks {
                if let profile = try? await profile(for: block.blockedUserId) {
                    loadedUsers.append(
                        SafetyBlockedUser(
                            id: block.id,
                            blockedUserId: block.blockedUserId,
                            profile: profile,
                            reason: block.reason,
                            createdAt: block.createdAt
                        )
                    )
                }
            }

            blockedUsers = loadedUsers
        } catch {
            blockedUsers = []
            errorMessage = String.localizedStringWithFormat(
                AppLanguageManager.localized("profile.blocked.loadFailedFormat"),
                error.localizedDescription
            )
        }
    }

    func unblockUser(blockerUserId: UUID, blockedUserId: UUID) async -> Bool {
        struct UnblockParams: Encodable {
            let p_blocked_user_id: UUID
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        _ = try? await supabase
            .rpc("unblock_user_everywhere", params: UnblockParams(p_blocked_user_id: blockedUserId))
            .execute()

        await deleteBlock(table: "blocks", blockerColumn: "blocker_user_id", blockedColumn: "blocked_user_id", blockerUserId: blockerUserId, blockedUserId: blockedUserId)
        await deleteBlock(table: "blocks", blockerColumn: "blocker_id", blockedColumn: "blocked_id", blockerUserId: blockerUserId, blockedUserId: blockedUserId)
        await deleteBlock(table: "user_blocks", blockerColumn: "blocker_user_id", blockedColumn: "blocked_user_id", blockerUserId: blockerUserId, blockedUserId: blockedUserId)

        guard !(await hasBlockInAnyTable(blockerUserId: blockerUserId, blockedUserId: blockedUserId)) else {
            errorMessage = AppLanguageManager.localized("profile.blocked.unblockStillBlocked")
            return false
        }

        blockedUsers.removeAll { $0.blockedUserId == blockedUserId }
        successMessage = AppLanguageManager.localized("profile.blocked.unblockSuccess")
        return true
    }

    private func deleteBlock(
        table: String,
        blockerColumn: String,
        blockedColumn: String,
        blockerUserId: UUID,
        blockedUserId: UUID
    ) async {
        _ = try? await supabase
            .from(table)
            .delete()
            .eq(blockerColumn, value: blockerUserId)
            .eq(blockedColumn, value: blockedUserId)
            .execute()
    }

    private func profile(for userId: UUID) async throws -> Profile {
        try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    private func loadBlockRows(table: String, blockerUserId: UUID) async throws -> [BlockListRow] {
        try await supabase
            .from(table)
            .select("id,blocked_user_id,reason,created_at")
            .eq("blocker_user_id", value: blockerUserId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    private func loadLegacyBlockRows(table: String, blockerUserId: UUID) async throws -> [BlockListRow] {
        let rows: [LegacyBlockListRow] = try await supabase
            .from(table)
            .select("id,blocked_id,reason,created_at")
            .eq("blocker_id", value: blockerUserId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map {
            BlockListRow(id: $0.id, blockedUserId: $0.blockedUserId, reason: $0.reason, createdAt: $0.createdAt)
        }
    }

    private func saveBlock<Payload: Encodable, FallbackPayload: Encodable>(
        payload: Payload,
        fallbackPayload: FallbackPayload,
        table: String
    ) async throws {
        try await saveBlock(payload: payload, fallbackPayload: fallbackPayload, legacyPayload: Optional<EmptyPayload>.none, table: table)
    }

    private func saveBlock<Payload: Encodable, FallbackPayload: Encodable, LegacyPayload: Encodable>(
        payload: Payload,
        fallbackPayload: FallbackPayload,
        legacyPayload: LegacyPayload?,
        table: String
    ) async throws {
        do {
            try await supabase
                .from(table)
                .upsert(payload, onConflict: "blocker_user_id,blocked_user_id")
                .execute()
            return
        } catch {
            do {
                try await supabase
                    .from(table)
                    .insert(payload)
                    .execute()
                return
            } catch {
                do {
                    try await supabase
                        .from(table)
                        .insert(fallbackPayload)
                        .execute()
                } catch {
                    guard let legacyPayload else { throw error }
                    try await supabase
                        .from(table)
                        .insert(legacyPayload)
                        .execute()
                }
            }
        }
    }

    private func hasBlockInAnyTable(blockerUserId: UUID, blockedUserId: UUID) async -> Bool {
        if (try? await hasBlock(table: "blocks", blockerUserId: blockerUserId, blockedUserId: blockedUserId)) == true {
            return true
        }

        if (try? await hasLegacyBlock(table: "blocks", blockerUserId: blockerUserId, blockedUserId: blockedUserId)) == true {
            return true
        }

        if (try? await hasBlock(table: "user_blocks", blockerUserId: blockerUserId, blockedUserId: blockedUserId)) == true {
            return true
        }

        return false
    }

    private func hasBlock(table: String, blockerUserId: UUID, blockedUserId: UUID) async throws -> Bool {
        struct BlockRow: Decodable {
            let id: UUID
        }

        let blocks: [BlockRow] = try await supabase
            .from(table)
            .select("id")
            .eq("blocker_user_id", value: blockerUserId)
            .eq("blocked_user_id", value: blockedUserId)
            .limit(1)
            .execute()
            .value

        return !blocks.isEmpty
    }

    private func hasLegacyBlock(table: String, blockerUserId: UUID, blockedUserId: UUID) async throws -> Bool {
        struct BlockRow: Decodable {
            let id: UUID
        }

        let blocks: [BlockRow] = try await supabase
            .from(table)
            .select("id")
            .eq("blocker_id", value: blockerUserId)
            .eq("blocked_id", value: blockedUserId)
            .limit(1)
            .execute()
            .value

        return !blocks.isEmpty
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SafetyError: LocalizedError {
    case blockDidNotPersist

    var errorDescription: String? {
        switch self {
        case .blockDidNotPersist:
            return "Block was submitted but did not save. Check Supabase blocks table RLS and unique index."
        }
    }
}

struct ReportProofAttachment {
    let data: Data
    let fileName: String
    let contentType: String
}
