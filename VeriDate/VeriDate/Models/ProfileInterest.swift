import Foundation

struct ProfileInterest: Codable, Hashable {
    let userId: UUID
    let interest: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case interest
        case createdAt = "created_at"
    }
}

