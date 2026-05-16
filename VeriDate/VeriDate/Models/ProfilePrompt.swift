import Foundation

struct ProfilePrompt: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    var prompt: String
    var answer: String
    var displayOrder: Int
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case prompt
        case answer
        case displayOrder = "display_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

