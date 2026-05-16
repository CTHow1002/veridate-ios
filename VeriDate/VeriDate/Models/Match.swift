import Foundation

struct Match: Identifiable, Codable, Hashable {
    let id: UUID
    let userOneId: UUID
    let userTwoId: UUID
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userOneId = "user_one_id"
        case userTwoId = "user_two_id"
        case createdAt = "created_at"
    }
}

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let matchId: UUID
    let senderId: UUID
    let body: String
    let isRead: Bool
    let deliveredAt: String?
    let readAt: String?
    let attachmentFilePath: String?
    let attachmentFileName: String?
    let attachmentContentType: String?
    let attachmentKind: String?
    let attachmentGroupId: UUID?
    let replyToMessageId: UUID?
    let editedAt: String?
    let deletedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderId = "sender_id"
        case body
        case isRead = "is_read"
        case deliveredAt = "delivered_at"
        case readAt = "read_at"
        case attachmentFilePath = "attachment_file_path"
        case attachmentFileName = "attachment_file_name"
        case attachmentContentType = "attachment_content_type"
        case attachmentKind = "attachment_kind"
        case attachmentGroupId = "attachment_group_id"
        case replyToMessageId = "reply_to_message_id"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        matchId: UUID,
        senderId: UUID,
        body: String,
        isRead: Bool,
        deliveredAt: String?,
        readAt: String?,
        attachmentFilePath: String?,
        attachmentFileName: String?,
        attachmentContentType: String?,
        attachmentKind: String?,
        attachmentGroupId: UUID?,
        replyToMessageId: UUID?,
        editedAt: String?,
        deletedAt: String?,
        createdAt: String
    ) {
        self.id = id
        self.matchId = matchId
        self.senderId = senderId
        self.body = body
        self.isRead = isRead
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.attachmentFilePath = attachmentFilePath
        self.attachmentFileName = attachmentFileName
        self.attachmentContentType = attachmentContentType
        self.attachmentKind = attachmentKind
        self.attachmentGroupId = attachmentGroupId
        self.replyToMessageId = replyToMessageId
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let readAt = try container.decodeIfPresent(String.self, forKey: .readAt)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.matchId = try container.decode(UUID.self, forKey: .matchId)
        self.senderId = try container.decode(UUID.self, forKey: .senderId)
        self.body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        self.isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? (readAt != nil)
        self.deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt)
        self.readAt = readAt
        self.attachmentFilePath = try container.decodeIfPresent(String.self, forKey: .attachmentFilePath)
        self.attachmentFileName = try container.decodeIfPresent(String.self, forKey: .attachmentFileName)
        self.attachmentContentType = try container.decodeIfPresent(String.self, forKey: .attachmentContentType)
        self.attachmentKind = try container.decodeIfPresent(String.self, forKey: .attachmentKind)
        self.attachmentGroupId = Self.decodeOptionalUUID(from: container, forKey: .attachmentGroupId)
        self.replyToMessageId = Self.decodeOptionalUUID(from: container, forKey: .replyToMessageId)
        self.editedAt = try container.decodeIfPresent(String.self, forKey: .editedAt)
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: Date())
    }

    private static func decodeOptionalUUID(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> UUID? {
        if let uuid = try? container.decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }

        guard let text = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.lowercased() != "null",
              trimmed.lowercased() != "nil" else {
            return nil
        }

        return UUID(uuidString: trimmed)
    }
}

struct MessageReaction: Identifiable, Codable, Hashable {
    let id: UUID
    let messageId: UUID
    let userId: UUID
    let emoji: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case userId = "user_id"
        case emoji
        case createdAt = "created_at"
    }
}
