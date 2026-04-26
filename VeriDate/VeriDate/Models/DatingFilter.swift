import Foundation

struct DatingFilter: Codable {
    var userId: UUID
    var preferredGender: GenderType?
    var minAge: Int
    var maxAge: Int
    var preferredCity: String?
    var minDistanceKm: Int
    var maxDistanceKm: Int
    var minHeightCm: Int?
    var maxHeightCm: Int?
    var educationLevel: String?
    var relationshipGoal: RelationshipIntention?
    var verifiedOnly: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case preferredGender = "preferred_gender"
        case minAge = "min_age"
        case maxAge = "max_age"
        case preferredCity = "preferred_city"
        case minDistanceKm = "min_distance_km"
        case maxDistanceKm = "max_distance_km"
        case minHeightCm = "min_height_cm"
        case maxHeightCm = "max_height_cm"
        case educationLevel = "education_level"
        case relationshipGoal = "relationship_goal"
        case verifiedOnly = "verified_only"
    }
}
