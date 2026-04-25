import Foundation
import Combine
import Supabase

@MainActor
final class VerificationUploadViewModel: ObservableObject {
    @Published var selfieData: Data?
    @Published var selfieFileName = "selfie.jpg"
    @Published var idDocumentURL: URL?
    @Published var jobProofURL: URL?
    @Published var educationProofURL: URL?
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var canSubmit: Bool {
        selfieData != nil && idDocumentURL != nil && jobProofURL != nil && educationProofURL != nil && !isSubmitting
    }

    func submitVerification(userId: UUID) async -> Bool {
        guard let selfieData, let idDocumentURL, let jobProofURL, let educationProofURL else {
            errorMessage = "Add all four verification files before submitting."
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let selfiePath = try await uploadData(
                selfieData,
                path: "\(userId.uuidString)/selfie/\(selfieFileName)",
                contentType: "image/jpeg",
                label: "selfie photo"
            )
            let idDocumentPath = try await uploadFile(idDocumentURL, userId: userId, folder: "id-document", label: "ID document")
            let jobProofPath = try await uploadFile(jobProofURL, userId: userId, folder: "job-proof", label: "job proof")
            let educationProofPath = try await uploadFile(educationProofURL, userId: userId, folder: "education-proof", label: "education proof")

            try await createVerificationSubmission(
                userId: userId,
                files: UploadedVerificationFiles(
                    selfiePath: selfiePath,
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
            let selfie_file_path: String
            let id_document_file_path: String
            let job_proof_file_path: String
            let education_proof_file_path: String
            let rejection_reason: String?
            let submitted_at: String
        }

        let payload = VerificationSubmissionPayload(
            user_id: userId,
            status: VerificationStatus.pending.rawValue,
            selfie_file_path: files.selfiePath,
            id_document_file_path: files.idDocumentPath,
            job_proof_file_path: files.jobProofPath,
            education_proof_file_path: files.educationProofPath,
            rejection_reason: nil,
            submitted_at: ISO8601DateFormatter().string(from: Date())
        )

        do {
            try await supabase
                .from("verification_submissions")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
            throw VerificationUploadError.submissionRow(underlying: error.localizedDescription)
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
    let selfiePath: String
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
