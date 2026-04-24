import Foundation

enum VerificationStatus: String, Codable {
    case unsubmitted
    case pending
    case verified
    case rejected
}

enum GenderType: String, Codable, CaseIterable {
    case male
    case female
    case non_binary
    case other
}

enum RelationshipIntention: String, Codable, CaseIterable {
    case serious_relationship
    case marriage
    case friendship_first
    case not_sure
}

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var fullName: String?
    var dateOfBirth: String?
    var age: Int?
    var gender: GenderType?
    var city: String?
    var country: String?
    var bio: String?
    var jobTitle: String?
    var companyName: String?
    var educationLevel: String?
    var schoolName: String?
    var heightCm: Int?
    var relationshipGoal: RelationshipIntention?
    var profilePhotoURL: String?
    var verificationStatus: VerificationStatus

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case age
        case gender
        case city
        case country
        case bio
        case jobTitle = "job_title"
        case companyName = "company_name"
        case educationLevel = "education_level"
        case schoolName = "school_name"
        case heightCm = "height_cm"
        case relationshipGoal = "relationship_goal"
        case profilePhotoURL = "profile_photo_url"
        case verificationStatus = "verification_status"
    }
}
