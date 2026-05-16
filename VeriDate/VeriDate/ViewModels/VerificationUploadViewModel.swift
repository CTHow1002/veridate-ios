import Foundation
import Combine
import Supabase

@MainActor
final class VerificationUploadViewModel: ObservableObject {
    @Published var selfieVideoData: Data?
    @Published var selfieVideoFileName = "selfie-video.mov"
    @Published var idDocument: VerificationDocument?
    @Published var jobProof: VerificationDocument?
    @Published var educationProof: VerificationDocument?
    @Published var isSubmitting = false
    @Published var isLoadingRejectionReason = false
    @Published var rejectionReason: String?
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client
    private var livenessPrompt: String {
        AppLanguageManager.localized("verificationUpload.video.livenessPromptInstruction")
    }

    func canSubmit(requiresJobProof: Bool = true, requiresEducationProof: Bool = true) -> Bool {
        selfieVideoData != nil
            && idDocument != nil
            && (!requiresJobProof || jobProof != nil)
            && (!requiresEducationProof || educationProof != nil)
            && !isSubmitting
    }

    func loadRejectionReason(userId: UUID) async {
        struct RejectedSubmission: Decodable {
            let rejection_reason: String?
        }

        isLoadingRejectionReason = true
        defer { isLoadingRejectionReason = false }

        do {
            let submissions: [RejectedSubmission] = try await supabase
                .from("verification_submissions")
                .select("rejection_reason")
                .eq("user_id", value: userId)
                .eq("status", value: VerificationStatus.rejected.rawValue)
                .order("reviewed_at", ascending: false)
                .limit(1)
                .execute()
                .value

            rejectionReason = submissions.first?.rejection_reason
        } catch {
            rejectionReason = nil
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.loadRejectionReasonFormat"), error.localizedDescription)
        }
    }

    func submitVerification(
        userId: UUID,
        requiresJobProof: Bool = true,
        requiresEducationProof: Bool = true
    ) async -> Bool {
        guard let selfieVideoData, let idDocument else {
            errorMessage = AppLanguageManager.localized("verificationUpload.error.videoAndICRequired")
            return false
        }

        guard !requiresJobProof || jobProof != nil else {
            errorMessage = AppLanguageManager.localized("verificationUpload.error.jobProofRequired")
            return false
        }

        guard !requiresEducationProof || educationProof != nil else {
            errorMessage = AppLanguageManager.localized("verificationUpload.error.educationProofRequired")
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            rejectionReason = nil
            let selfieVideoPath = try await uploadData(
                selfieVideoData,
                path: "\(userId.uuidString)/selfie-video/\(selfieVideoFileName)",
                contentType: "video/quicktime",
                label: AppLanguageManager.localized("verificationUpload.uploadLabel.selfieVideo")
            )
            let idDocumentPath = try await uploadDocument(idDocument, userId: userId, folder: "id-document", label: AppLanguageManager.localized("verificationUpload.uploadLabel.idDocument"))
            let jobProofPath = requiresJobProof
                ? try await uploadDocument(jobProof!, userId: userId, folder: "job-proof", label: AppLanguageManager.localized("verificationUpload.uploadLabel.jobProof"))
                : ""
            let educationProofPath = requiresEducationProof
                ? try await uploadDocument(educationProof!, userId: userId, folder: "education-proof", label: AppLanguageManager.localized("verificationUpload.uploadLabel.educationProof"))
                : ""

            try await createVerificationSubmission(
                userId: userId,
                files: UploadedVerificationFiles(
                    selfieVideoPath: selfieVideoPath,
                    idDocumentPath: idDocumentPath,
                    jobProofPath: jobProofPath,
                    educationProofPath: educationProofPath
                )
            )

            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func uploadDocument(_ document: VerificationDocument, userId: UUID, folder: String, label: String) async throws -> String {
        let data: Data

        if let fileURL = document.fileURL {
            data = try readFileData(from: fileURL)
        } else if let photoData = document.data {
            data = photoData
        } else {
            throw VerificationUploadError.missingDocument(label: label)
        }

        let fileName = cleanFileName(document.fileName, fallback: "\(folder).pdf")

        return try await uploadData(
            data,
            path: "\(userId.uuidString)/\(folder)/\(fileName)",
            contentType: document.contentType,
            label: label
        )
    }

    private func readFileData(from url: URL) throws -> Data {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try Data(contentsOf: url)
    }

    private func uploadData(_ data: Data, path: String, contentType: String, label: String) async throws -> String {
        do {
            try await supabase.storage
                .from("verification-documents")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: contentType, upsert: true)
                )
            return path
        } catch {
            throw VerificationUploadError.blockedStep(label: label, path: path, underlying: error.localizedDescription)
        }
    }

    private func createVerificationSubmission(userId: UUID, files: UploadedVerificationFiles) async throws {
        struct VerificationSubmissionPayload: Encodable {
            let user_id: UUID
            let status: String
            let selfie_video_file_path: String
            let liveness_prompt: String
            let id_document_file_path: String
            let job_proof_file_path: String
            let education_proof_file_path: String
            let rejection_reason: String?
            let submitted_at: String
        }

        struct VerificationSubmissionPayloadWithoutPrompt: Encodable {
            let user_id: UUID
            let status: String
            let selfie_video_file_path: String
            let id_document_file_path: String
            let job_proof_file_path: String
            let education_proof_file_path: String
            let rejection_reason: String?
            let submitted_at: String
        }

        struct LegacyVerificationSubmissionPayload: Encodable {
            let user_id: UUID
            let status: String
            let selfie_file_path: String
            let id_document_file_path: String
            let job_proof_file_path: String
            let education_proof_file_path: String
            let rejection_reason: String?
            let submitted_at: String
        }

        let submittedAt = ISO8601DateFormatter().string(from: Date())
        let payload = VerificationSubmissionPayload(
            user_id: userId,
            status: VerificationStatus.pending.rawValue,
            selfie_video_file_path: files.selfieVideoPath,
            liveness_prompt: livenessPrompt,
            id_document_file_path: files.idDocumentPath,
            job_proof_file_path: files.jobProofPath,
            education_proof_file_path: files.educationProofPath,
            rejection_reason: nil,
            submitted_at: submittedAt
        )

        do {
            try await supabase
                .from("verification_submissions")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            let underlying = error.localizedDescription
            guard underlying.localizedCaseInsensitiveContains("liveness_prompt") ||
                    underlying.localizedCaseInsensitiveContains("selfie_video_file_path") else {
                throw VerificationUploadError.submissionRow(underlying: underlying)
            }

            if underlying.localizedCaseInsensitiveContains("selfie_video_file_path") {
                let legacyPayload = LegacyVerificationSubmissionPayload(
                    user_id: userId,
                    status: VerificationStatus.pending.rawValue,
                    selfie_file_path: files.selfieVideoPath,
                    id_document_file_path: files.idDocumentPath,
                    job_proof_file_path: files.jobProofPath,
                    education_proof_file_path: files.educationProofPath,
                    rejection_reason: nil,
                    submitted_at: submittedAt
                )

                do {
                    try await supabase
                        .from("verification_submissions")
                        .upsert(legacyPayload, onConflict: "user_id")
                        .execute()
                    return
                } catch {
                    throw VerificationUploadError.submissionRow(underlying: error.localizedDescription)
                }
            }

            let promptFallbackPayload = VerificationSubmissionPayloadWithoutPrompt(
                user_id: userId,
                status: VerificationStatus.pending.rawValue,
                selfie_video_file_path: files.selfieVideoPath,
                id_document_file_path: files.idDocumentPath,
                job_proof_file_path: files.jobProofPath,
                education_proof_file_path: files.educationProofPath,
                rejection_reason: nil,
                submitted_at: submittedAt
            )

            do {
                try await supabase
                    .from("verification_submissions")
                    .upsert(promptFallbackPayload, onConflict: "user_id")
                    .execute()
            } catch {
                throw VerificationUploadError.submissionRow(underlying: error.localizedDescription)
            }
        }
    }

    private func cleanFileName(_ fileName: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = fileName
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()

        return cleaned.isEmpty ? fallback : cleaned
    }
}

struct VerificationDocument {
    let fileName: String
    let contentType: String
    let data: Data?
    let fileURL: URL?

    var displayName: String {
        fileName
    }

    static func file(url: URL, contentType: String) -> VerificationDocument {
        VerificationDocument(
            fileName: url.lastPathComponent,
            contentType: contentType,
            data: nil,
            fileURL: url
        )
    }

    static func photo(data: Data, fileName: String, contentType: String) -> VerificationDocument {
        VerificationDocument(
            fileName: fileName,
            contentType: contentType,
            data: data,
            fileURL: nil
        )
    }
}

private struct UploadedVerificationFiles {
    let selfieVideoPath: String
    let idDocumentPath: String
    let jobProofPath: String
    let educationProofPath: String
}

private enum VerificationUploadError: LocalizedError {
    case missingDocument(label: String)
    case blockedStep(label: String, path: String, underlying: String)
    case submissionRow(underlying: String)

    var errorDescription: String? {
        switch self {
        case .missingDocument(let label):
            return String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.missingDocumentFormat"), label)
        case .blockedStep(let label, let path, let underlying):
            return String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.blockedStepFormat"), label, path, underlying)
        case .submissionRow(let underlying):
            return String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.submissionRowFormat"), underlying)
        }
    }
}
