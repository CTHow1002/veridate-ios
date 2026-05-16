import Foundation
import Supabase

struct ChatAttachmentFile {
    let data: Data
    let fileName: String
    let contentType: String
    let kind: String
}

final class ChatAttachmentService {
    static let shared = ChatAttachmentService()

    private let bucket = "chat-attachments"
    private let supabase = SupabaseManager.shared.client

    private init() {}

    func uploadAttachment(matchId: UUID, senderId: UUID, attachment: ChatAttachmentFile) async throws -> String {
        let safeName = cleanFileName(attachment.fileName, fallback: defaultFileName(for: attachment))
        let path = "\(matchId.uuidString)/\(senderId.uuidString)/\(UUID().uuidString)-\(safeName)"

        try await supabase.storage
            .from(bucket)
            .upload(
                path,
                data: attachment.data,
                options: FileOptions(contentType: attachment.contentType, upsert: false)
            )

        return path
    }

    func signedURL(for path: String) async throws -> URL {
        try await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: 3600)
    }

    private func cleanFileName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                result.append(character)
            }

        return cleaned.isEmpty ? fallback : cleaned
    }

    private func defaultFileName(for attachment: ChatAttachmentFile) -> String {
        if attachment.kind == "image" {
            return "photo.jpg"
        }

        if attachment.kind == "audio" {
            return "voice-message.m4a"
        }

        if attachment.kind == "video" {
            return "video.mov"
        }

        return "attachment"
    }
}
