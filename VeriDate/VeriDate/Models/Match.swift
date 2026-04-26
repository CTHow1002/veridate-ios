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
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderId = "sender_id"
        case body
        case isRead = "is_read"
        case deliveredAt = "delivered_at"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}
