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
    var latitude: Double?
    var longitude: Double?
    var bio: String?
    var jobTitle: String?
    var companyName: String?
    var educationLevel: String?
    var schoolName: String?
    var heightCm: Int?
    var relationshipGoal: RelationshipIntention?
    var profilePhotoURL: String?
    var isOnline: Bool
    var lastSeenAt: String?
    var isBanned: Bool
    var verificationStatus: VerificationStatus

    var hasCompletedBasicProfile: Bool {
        guard let fullName, !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case age
        case gender
        case city
        case country
        case latitude
        case longitude
        case bio
        case jobTitle = "job_title"
        case companyName = "company_name"
        case educationLevel = "education_level"
        case schoolName = "school_name"
        case heightCm = "height_cm"
        case relationshipGoal = "relationship_goal"
        case profilePhotoURL = "profile_photo_url"
        case isOnline = "is_online"
        case lastSeenAt = "last_seen_at"
        case isBanned = "is_banned"
        case verificationStatus = "verification_status"
    }

    init(
        id: UUID,
        fullName: String? = nil,
        dateOfBirth: String? = nil,
        age: Int? = nil,
        gender: GenderType? = nil,
        city: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        bio: String? = nil,
        jobTitle: String? = nil,
        companyName: String? = nil,
        educationLevel: String? = nil,
        schoolName: String? = nil,
        heightCm: Int? = nil,
        relationshipGoal: RelationshipIntention? = nil,
        profilePhotoURL: String? = nil,
        isOnline: Bool = false,
        lastSeenAt: String? = nil,
        isBanned: Bool = false,
        verificationStatus: VerificationStatus = .unsubmitted
    ) {
        self.id = id
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
        self.age = age
        self.gender = gender
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.bio = bio
        self.jobTitle = jobTitle
        self.companyName = companyName
        self.educationLevel = educationLevel
        self.schoolName = schoolName
        self.heightCm = heightCm
        self.relationshipGoal = relationshipGoal
        self.profilePhotoURL = profilePhotoURL
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.isBanned = isBanned
        self.verificationStatus = verificationStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(GenderType.self, forKey: .gender)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        jobTitle = try container.decodeIfPresent(String.self, forKey: .jobTitle)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        educationLevel = try container.decodeIfPresent(String.self, forKey: .educationLevel)
        schoolName = try container.decodeIfPresent(String.self, forKey: .schoolName)
        heightCm = try container.decodeIfPresent(Int.self, forKey: .heightCm)
        relationshipGoal = try container.decodeIfPresent(RelationshipIntention.self, forKey: .relationshipGoal)
        profilePhotoURL = try container.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        verificationStatus = try container.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? .unsubmitted
    }
}
