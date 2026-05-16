import Foundation

struct ProfilePhoto: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let photoPath: String
    let displayOrder: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case photoPath = "photo_path"
        case displayOrder = "display_order"
        case createdAt = "created_at"
    }
}
