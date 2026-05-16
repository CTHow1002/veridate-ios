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
    var preferredGenders: String?
    var maritalStatuses: String?
    var races: String?
    var religions: String?
    var educationLevels: String?
    var relationshipGoals: String?
    var smokingOptions: String?
    var drinkingOptions: String?
    var exerciseOptions: String?
    var petOptions: String?
    var communicationStyles: String?
    var loveLanguages: String?
    var mbtis: String?
    var languageOptions: String?
    var familyPlansOptions: String?
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
        case preferredGenders = "preferred_genders"
        case maritalStatuses = "marital_statuses"
        case races
        case religions
        case educationLevels = "education_levels"
        case relationshipGoals = "relationship_goals"
        case smokingOptions = "smoking_options"
        case drinkingOptions = "drinking_options"
        case exerciseOptions = "exercise_options"
        case petOptions = "pet_options"
        case communicationStyles = "communication_styles"
        case loveLanguages = "love_languages"
        case mbtis
        case languageOptions = "language_options"
        case familyPlansOptions = "family_plans_options"
        case verifiedOnly = "verified_only"
    }
}
