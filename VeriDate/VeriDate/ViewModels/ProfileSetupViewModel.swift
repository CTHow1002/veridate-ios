import Foundation
import Combine
import CoreLocation
import Supabase

@MainActor
final class ProfileSetupViewModel: ObservableObject {
    static let educationLevels = ["Primary school", "High school", "Diploma", "Degree", "Master", "PhD"]

    @Published var fullName = ""
    @Published var displayName = ""
    @Published var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @Published var gender: GenderType = .male
    @Published var maritalStatus: MaritalStatus?
    @Published var race = ""
    @Published var religion = ""
    @Published var city = ""
    @Published var hometown = ""
    @Published var currentlyLiving = ""
    @Published var isStudent = false
    @Published var isUnemployed = false
    @Published var jobTitle = ""
    @Published var companyName = ""
    @Published var educationLevel = "Degree"
    @Published var schoolName = ""
    @Published var heightCm = 170
    @Published var relationshipGoal: RelationshipIntention = .serious_relationship
    @Published var genderInterest: GenderInterest = .opposite_gender
    @Published var smoking = ""
    @Published var drinking = ""
    @Published var exercise = ""
    @Published var bio = ""
    @Published var pets = ""
    @Published var communicationStyle = ""
    @Published var loveLanguage = ""
    @Published var mbti = ""
    @Published var languages = ""
    @Published var familyPlans = ""
    @Published var errorMessage: String?
    @Published var isSaving = false

    static let smokingOptions = ["", "Never", "Socially", "Sometimes", "Often", "Prefer not to say"]
    static let drinkingOptions = ["", "Never", "Socially", "Sometimes", "Often", "Prefer not to say"]
    static let exerciseOptions = ["", "Daily", "A few times a week", "Sometimes", "Rarely", "Prefer not to say"]
    static let raceOptions = ["", "Malay", "Chinese", "Indian", "Iban", "Kadazan", "Mixed", "Other", "Prefer not to say"]
    static let religionOptions = ["", "Islam", "Buddhism", "Christianity", "Hinduism", "Taoism", "Atheist", "Agnostic", "Spiritual", "Other", "Prefer not to say"]
    static let petOptions = ["Dog", "Cat", "Fish", "Bird", "Rabbit", "Hamster", "Reptile", "Have pets", "Want pets", "No pet but love them", "Not a pet person", "Allergic to pets", "Prefer not to say"]
    static let communicationStyleOptions = ["", "Responsive texter", "Thoughtful texter", "Phone calls", "Video calls", "Voice messages", "In-person conversations", "Plans ahead", "Spontaneous check-ins", "Low-maintenance communicator"]
    static let loveLanguageOptions = ["", "Quality time", "Words of affirmation", "Acts of service", "Physical touch", "Receiving gifts", "Not sure yet"]
    static let mbtiOptions = ["", "ISTJ", "ISFJ", "INFJ", "INTJ", "ISTP", "ISFP", "INFP", "INTP", "ESTP", "ESFP", "ENFP", "ENTP", "ESTJ", "ESFJ", "ENFJ", "ENTJ", "NOT SURE"]
    static let familyPlansOptions = ["", "Want children", "Open to children", "Do not want children", "Have children", "Prefer not to say"]
    static let languageOptions = ["English", "Malay", "Mandarin", "Cantonese", "Tamil", "Hokkien", "Hakka", "Teochew", "Japanese", "Korean", "Arabic", "Hindi", "Indonesian", "Thai", "Other"]

    private let supabase = SupabaseManager.shared.client
    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func save(userId: UUID, coordinate: CLLocationCoordinate2D?) async -> Bool {
        errorMessage = nil

        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = AppLanguageManager.localized("profileSetup.error.fullNameRequired")
            return false
        }

        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = AppLanguageManager.localized("profileSetup.error.displayNameRequired")
            return false
        }

        isSaving = true
        defer { isSaving = false }

        struct UpdateProfile: Encodable {
            let full_name: String
            let display_name: String?
            let date_of_birth: String?
            let gender: String
            let marital_status: String?
            let race: String?
            let religion: String?
            let city: String?
            let hometown: String?
            let currently_living: String?
            let latitude: Double?
            let longitude: Double?
            let job_title: String
            let company_name: String
            let education_level: String
            let school_name: String
            let height_cm: Int?
            let relationship_goal: String
            let gender_interest: String
            let smoking: String?
            let drinking: String?
            let exercise: String?
            let bio: String?
            let pets: String?
            let communication_style: String?
            let love_language: String?
            let mbti: String?
            let languages: String?
            let family_plans: String?
        }

        let payload = UpdateProfile(
            full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            display_name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            date_of_birth: Self.birthDateFormatter.string(from: dateOfBirth),
            gender: gender.rawValue,
            marital_status: maritalStatus?.rawValue,
            race: cleanedOptional(race),
            religion: cleanedOptional(religion),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : city.trimmingCharacters(in: .whitespacesAndNewlines),
            hometown: hometown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hometown.trimmingCharacters(in: .whitespacesAndNewlines),
            currently_living: currentlyLiving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : currentlyLiving.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            job_title: savedJobTitle,
            company_name: savedCompanyName,
            education_level: educationLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            school_name: schoolName.trimmingCharacters(in: .whitespacesAndNewlines),
            height_cm: heightCm,
            relationship_goal: relationshipGoal.rawValue,
            gender_interest: genderInterest.rawValue,
            smoking: cleanedOptional(smoking),
            drinking: cleanedOptional(drinking),
            exercise: cleanedOptional(exercise),
            bio: cleanedOptional(bio),
            pets: cleanedOptional(pets),
            communication_style: cleanedOptional(communicationStyle),
            love_language: cleanedOptional(loveLanguage),
            mbti: cleanedOptional(mbti),
            languages: cleanedOptional(languages),
            family_plans: cleanedOptional(familyPlans)
        )

        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: userId)
                .execute()
            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.error.saveProfileFormat"), error.localizedDescription)
            return false
        }
    }

    var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        let youngest = calendar.date(byAdding: .year, value: -18, to: Date()) ?? Date()
        return oldest...youngest
    }

    var hasNoWorkVerification: Bool {
        isStudent || isUnemployed
    }

    private func cleanedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var savedJobTitle: String {
        if isStudent { return "Student" }
        if isUnemployed { return "Unemployed" }
        return jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedCompanyName: String {
        if isStudent || isUnemployed { return "" }
        return companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
