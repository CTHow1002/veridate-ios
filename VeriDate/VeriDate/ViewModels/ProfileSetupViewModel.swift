import Foundation
import Combine
import Supabase

@MainActor
final class ProfileSetupViewModel: ObservableObject {
    static let educationLevels = ["Primary school", "High school", "Diploma", "Degree", "Master", "PhD"]

    @Published var fullName = ""
    @Published var dateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @Published var gender: GenderType = .male
    @Published var city = ""
    @Published var bio = ""
    @Published var jobTitle = ""
    @Published var companyName = ""
    @Published var educationLevel = "Degree"
    @Published var schoolName = ""
    @Published var heightCm = 170
    @Published var relationshipGoal: RelationshipIntention = .serious_relationship
    @Published var errorMessage: String?
    @Published var isSaving = false

    private let supabase = SupabaseManager.shared.client
    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func save(userId: UUID) async -> Bool {
        errorMessage = nil

        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your full name before continuing."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        struct UpdateProfile: Encodable {
            let full_name: String
            let date_of_birth: String?
            let gender: String
            let city: String
            let bio: String
            let job_title: String
            let company_name: String
            let education_level: String
            let school_name: String
            let height_cm: Int?
            let relationship_goal: String
        }

        let payload = UpdateProfile(
            full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            date_of_birth: Self.birthDateFormatter.string(from: dateOfBirth),
            gender: gender.rawValue,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            job_title: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            company_name: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            education_level: educationLevel.trimmingCharacters(in: .whitespacesAndNewlines),
            school_name: schoolName.trimmingCharacters(in: .whitespacesAndNewlines),
            height_cm: heightCm,
            relationship_goal: relationshipGoal.rawValue
        )

        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: userId)
                .execute()
            return true
        } catch {
            errorMessage = "Could not save your profile. \(error.localizedDescription)"
            return false
        }
    }

    var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -100, to: Date()) ?? Date()
        let youngest = calendar.date(byAdding: .year, value: -18, to: Date()) ?? Date()
        return oldest...youngest
    }
}
