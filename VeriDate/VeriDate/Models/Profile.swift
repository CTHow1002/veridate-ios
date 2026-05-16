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

enum MaritalStatus: String, Codable, CaseIterable {
    case single
    case divorced
    case widowed
    case separated
    case prefer_not_to_say
}

enum GenderInterest: String, Codable, CaseIterable {
    case opposite_gender
    case men
    case women
    case everyone
}

enum LifestyleProfileField: String, Codable, CaseIterable {
    case never
    case socially
    case sometimes
    case often
    case prefer_not_to_say
}

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: String?
    var fullName: String?
    var displayName: String?
    var dateOfBirth: String?
    var age: Int?
    var gender: GenderType?
    var maritalStatus: MaritalStatus?
    var race: String?
    var religion: String?
    var hometown: String?
    var currentlyLiving: String?
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
    var genderInterest: GenderInterest?
    var smoking: String?
    var drinking: String?
    var exercise: String?
    var pets: String?
    var communicationStyle: String?
    var loveLanguage: String?
    var mbti: String?
    var languages: String?
    var familyPlans: String?
    var profilePhotoURL: String?
    var isOnline: Bool
    var lastSeenAt: String?
    var isBanned: Bool
    var banUntil: String?
    var banMessage: String?
    var banDetails: String?
    var warningMessage: String?
    var warningDetails: String?
    var warnedAt: String?
    var warningUntil: String?
    var isDeactivated: Bool
    var isDiscoverable: Bool
    var accountDeletionRequestedAt: String?
    var accountDeletionScheduledAt: String?
    var verificationStatus: VerificationStatus

    var publicName: String? {
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        return nil
    }

    var isCurrentlyBanned: Bool {
        guard isBanned else { return false }
        guard let banUntil, let date = Self.parseDate(banUntil) else { return true }
        return date > Date()
    }

    var banUntilDate: Date? {
        guard let banUntil else { return nil }
        return Self.parseDate(banUntil)
    }

    var hasActiveWarning: Bool {
        guard let warningMessage else { return false }
        guard !warningMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let warningUntil, let date = Self.parseDate(warningUntil) else { return true }
        return date > Date()
    }

    var warningUntilDate: Date? {
        guard let warningUntil else { return nil }
        return Self.parseDate(warningUntil)
    }

    var hasCompletedBasicProfile: Bool {
        guard let publicName, !publicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return true
    }

    var displayAge: Int? {
        Self.calculatedAge(from: dateOfBirth) ?? age
    }

    var horoscope: String? {
        Self.horoscope(from: dateOfBirth)
    }

    var hasNonWorkingStatus: Bool {
        let title = jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.localizedCaseInsensitiveCompare("Student") == .orderedSame
            || title.localizedCaseInsensitiveCompare("Unemployed") == .orderedSame
    }

    var displayJobTitle: String? {
        let title = jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }

    var displayCompanyName: String? {
        guard !hasNonWorkingStatus else { return nil }
        let company = companyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return company?.isEmpty == false ? company : nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case fullName = "full_name"
        case displayName = "display_name"
        case dateOfBirth = "date_of_birth"
        case age
        case gender
        case maritalStatus = "marital_status"
        case race
        case religion
        case hometown
        case currentlyLiving = "currently_living"
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
        case genderInterest = "gender_interest"
        case smoking
        case drinking
        case exercise
        case pets
        case communicationStyle = "communication_style"
        case loveLanguage = "love_language"
        case mbti
        case languages
        case familyPlans = "family_plans"
        case profilePhotoURL = "profile_photo_url"
        case isOnline = "is_online"
        case lastSeenAt = "last_seen_at"
        case isBanned = "is_banned"
        case banUntil = "ban_until"
        case banMessage = "ban_message"
        case banDetails = "ban_details"
        case warningMessage = "warning_message"
        case warningDetails = "warning_details"
        case warnedAt = "warned_at"
        case warningUntil = "warning_until"
        case isDeactivated = "is_deactivated"
        case isDiscoverable = "is_discoverable"
        case accountDeletionRequestedAt = "account_deletion_requested_at"
        case accountDeletionScheduledAt = "account_deletion_scheduled_at"
        case verificationStatus = "verification_status"
    }

    init(
        id: UUID,
        createdAt: String? = nil,
        fullName: String? = nil,
        displayName: String? = nil,
        dateOfBirth: String? = nil,
        age: Int? = nil,
        gender: GenderType? = nil,
        maritalStatus: MaritalStatus? = nil,
        race: String? = nil,
        religion: String? = nil,
        hometown: String? = nil,
        currentlyLiving: String? = nil,
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
        genderInterest: GenderInterest? = nil,
        smoking: String? = nil,
        drinking: String? = nil,
        exercise: String? = nil,
        pets: String? = nil,
        communicationStyle: String? = nil,
        loveLanguage: String? = nil,
        mbti: String? = nil,
        languages: String? = nil,
        familyPlans: String? = nil,
        profilePhotoURL: String? = nil,
        isOnline: Bool = false,
        lastSeenAt: String? = nil,
        isBanned: Bool = false,
        banUntil: String? = nil,
        banMessage: String? = nil,
        banDetails: String? = nil,
        warningMessage: String? = nil,
        warningDetails: String? = nil,
        warnedAt: String? = nil,
        warningUntil: String? = nil,
        isDeactivated: Bool = false,
        isDiscoverable: Bool = true,
        accountDeletionRequestedAt: String? = nil,
        accountDeletionScheduledAt: String? = nil,
        verificationStatus: VerificationStatus = .unsubmitted
    ) {
        self.id = id
        self.createdAt = createdAt
        self.fullName = fullName
        self.displayName = displayName
        self.dateOfBirth = dateOfBirth
        self.age = age
        self.gender = gender
        self.maritalStatus = maritalStatus
        self.race = race
        self.religion = religion
        self.hometown = hometown
        self.currentlyLiving = currentlyLiving
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
        self.genderInterest = genderInterest
        self.smoking = smoking
        self.drinking = drinking
        self.exercise = exercise
        self.pets = pets
        self.communicationStyle = communicationStyle
        self.loveLanguage = loveLanguage
        self.mbti = mbti
        self.languages = languages
        self.familyPlans = familyPlans
        self.profilePhotoURL = profilePhotoURL
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
        self.isBanned = isBanned
        self.banUntil = banUntil
        self.banMessage = banMessage
        self.banDetails = banDetails
        self.warningMessage = warningMessage
        self.warningDetails = warningDetails
        self.warnedAt = warnedAt
        self.warningUntil = warningUntil
        self.isDeactivated = isDeactivated
        self.isDiscoverable = isDiscoverable
        self.accountDeletionRequestedAt = accountDeletionRequestedAt
        self.accountDeletionScheduledAt = accountDeletionScheduledAt
        self.verificationStatus = verificationStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        gender = try container.decodeIfPresent(GenderType.self, forKey: .gender)
        maritalStatus = try container.decodeIfPresent(MaritalStatus.self, forKey: .maritalStatus)
        race = try container.decodeIfPresent(String.self, forKey: .race)
        religion = try container.decodeIfPresent(String.self, forKey: .religion)
        hometown = try container.decodeIfPresent(String.self, forKey: .hometown)
        currentlyLiving = try container.decodeIfPresent(String.self, forKey: .currentlyLiving)
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
        genderInterest = try container.decodeIfPresent(GenderInterest.self, forKey: .genderInterest)
        smoking = try container.decodeIfPresent(String.self, forKey: .smoking)
        drinking = try container.decodeIfPresent(String.self, forKey: .drinking)
        exercise = try container.decodeIfPresent(String.self, forKey: .exercise)
        pets = try container.decodeIfPresent(String.self, forKey: .pets)
        communicationStyle = try container.decodeIfPresent(String.self, forKey: .communicationStyle)
        loveLanguage = try container.decodeIfPresent(String.self, forKey: .loveLanguage)
        mbti = try container.decodeIfPresent(String.self, forKey: .mbti)
        languages = try container.decodeIfPresent(String.self, forKey: .languages)
        familyPlans = try container.decodeIfPresent(String.self, forKey: .familyPlans)
        profilePhotoURL = try container.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        // 🔥 More resilient decoding (handles unexpected types from Supabase)
        if let boolValue = try? container.decode(Bool.self, forKey: .isOnline) {
            isOnline = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .isOnline) {
            isOnline = intValue == 1
        } else if let stringValue = try? container.decode(String.self, forKey: .isOnline) {
            isOnline = (stringValue as NSString).boolValue
        } else {
            isOnline = false
        }
        // 🔥 Handle timestamp or string formats
        if let stringValue = try? container.decode(String.self, forKey: .lastSeenAt) {
            lastSeenAt = stringValue
        } else if let dateValue = try? container.decode(Date.self, forKey: .lastSeenAt) {
            lastSeenAt = ISO8601DateFormatter().string(from: dateValue)
        } else {
            lastSeenAt = nil
        }
        isBanned = try container.decodeIfPresent(Bool.self, forKey: .isBanned) ?? false
        banUntil = try container.decodeIfPresent(String.self, forKey: .banUntil)
        banMessage = try container.decodeIfPresent(String.self, forKey: .banMessage)
        banDetails = try container.decodeIfPresent(String.self, forKey: .banDetails)
        warningMessage = try container.decodeIfPresent(String.self, forKey: .warningMessage)
        warningDetails = try container.decodeIfPresent(String.self, forKey: .warningDetails)
        warnedAt = try container.decodeIfPresent(String.self, forKey: .warnedAt)
        warningUntil = try container.decodeIfPresent(String.self, forKey: .warningUntil)
        isDeactivated = try container.decodeIfPresent(Bool.self, forKey: .isDeactivated) ?? false
        isDiscoverable = try container.decodeIfPresent(Bool.self, forKey: .isDiscoverable) ?? true
        accountDeletionRequestedAt = Self.decodeTimestamp(from: container, forKey: .accountDeletionRequestedAt)
        accountDeletionScheduledAt = Self.decodeTimestamp(from: container, forKey: .accountDeletionScheduledAt)
        verificationStatus = try container.decodeIfPresent(VerificationStatus.self, forKey: .verificationStatus) ?? .unsubmitted
    }

    private static func decodeTimestamp(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }

        if let dateValue = try? container.decode(Date.self, forKey: key) {
            return ISO8601DateFormatter().string(from: dateValue)
        }

        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func calculatedAge(from dateOfBirth: String?) -> Int? {
        guard let rawValue = dateOfBirth?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        let birthDate: Date?
        if rawValue.count >= 10 {
            let dateOnly = String(rawValue.prefix(10))
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            birthDate = formatter.date(from: dateOnly)
        } else {
            birthDate = parseDate(rawValue)
        }

        guard let birthDate else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let startOfBirthDay = calendar.startOfDay(for: birthDate)
        let startOfToday = calendar.startOfDay(for: Date())
        guard startOfBirthDay <= startOfToday else { return nil }

        return calendar.dateComponents([.year], from: startOfBirthDay, to: startOfToday).year
    }

    private static func horoscope(from dateOfBirth: String?) -> String? {
        guard let rawValue = dateOfBirth?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.count >= 10 else {
            return nil
        }

        let monthString = String(rawValue.dropFirst(5).prefix(2))
        let dayString = String(rawValue.dropFirst(8).prefix(2))

        guard let month = Int(monthString), let day = Int(dayString) else {
            return nil
        }

        switch (month, day) {
        case (3, 21...31), (4, 1...19): return "Aries"
        case (4, 20...30), (5, 1...20): return "Taurus"
        case (5, 21...31), (6, 1...20): return "Gemini"
        case (6, 21...30), (7, 1...22): return "Cancer"
        case (7, 23...31), (8, 1...22): return "Leo"
        case (8, 23...31), (9, 1...22): return "Virgo"
        case (9, 23...30), (10, 1...22): return "Libra"
        case (10, 23...31), (11, 1...21): return "Scorpio"
        case (11, 22...30), (12, 1...21): return "Sagittarius"
        case (12, 22...31), (1, 1...19): return "Capricorn"
        case (1, 20...31), (2, 1...18): return "Aquarius"
        case (2, 19...29), (3, 1...20): return "Pisces"
        default: return nil
        }
    }
}
