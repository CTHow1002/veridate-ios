import Foundation
import Combine
import Supabase

@MainActor
final class VerificationUploadViewModel: ObservableObject {
    @Published var selfieVideoData: Data?
    @Published var selfieVideoFileName = "selfie-video.mov"
    @Published var livenessPrompt = "Turn your head slightly left, then look back at the camera."
    @Published var idDocumentURL: URL?
    @Published var jobProofURL: URL?
    @Published var educationProofURL: URL?
    @Published var isSubmitting = false
    @Published var isLoadingRejectionReason = false
    @Published var rejectionReason: String?
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var canSubmit: Bool {
        selfieVideoData != nil && idDocumentURL != nil && jobProofURL != nil && educationProofURL != nil && !isSubmitting
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
            errorMessage = "Could not load rejection reason. \(error.localizedDescription)"
        }
    }

    func submitVerification(userId: UUID) async -> Bool {
        guard let selfieVideoData, let idDocumentURL, let jobProofURL, let educationProofURL else {
            errorMessage = "Add your verification video and all three documents before submitting."
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
                label: "selfie verification video"
            )
            let idDocumentPath = try await uploadFile(idDocumentURL, userId: userId, folder: "id-document", label: "ID document")
            let jobProofPath = try await uploadFile(jobProofURL, userId: userId, folder: "job-proof", label: "job proof")
            let educationProofPath = try await uploadFile(educationProofURL, userId: userId, folder: "education-proof", label: "education proof")

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

    private func uploadFile(_ url: URL, userId: UUID, folder: String, label: String) async throws -> String {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let fileName = cleanFileName(url.lastPathComponent, fallback: "\(folder).pdf")
        let contentType = contentType(for: url)

        return try await uploadData(
            data,
            path: "\(userId.uuidString)/\(folder)/\(fileName)",
            contentType: contentType,
            label: label
        )
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

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        case "mov":
            return "video/quicktime"
        case "mp4", "m4v":
            return "video/mp4"
        default:
            return "application/octet-stream"
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

private struct UploadedVerificationFiles {
    let selfieVideoPath: String
    let idDocumentPath: String
    let jobProofPath: String
    let educationProofPath: String
}

private enum VerificationUploadError: LocalizedError {
    case blockedStep(label: String, path: String, underlying: String)
    case submissionRow(underlying: String)

    var errorDescription: String? {
        switch self {
        case .blockedStep(let label, let path, let underlying):
            return "Supabase blocked the \(label) upload at \(path). \(underlying)"
        case .submissionRow(let underlying):
            return "Files uploaded, but Supabase blocked creating the verification submission row. \(underlying)"
        }
    }
}
