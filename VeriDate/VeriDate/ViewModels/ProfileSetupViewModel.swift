import Foundation
import Combine
import Supabase
import PostgREST

@MainActor
final class ProfileSetupViewModel: ObservableObject {
    @Published var fullName = ""
    @Published var dateOfBirth = ""
    @Published var gender: GenderType = .male
    @Published var city = ""
    @Published var bio = ""
    @Published var jobTitle = ""
    @Published var companyName = ""
    @Published var educationLevel = ""
    @Published var schoolName = ""
    @Published var heightCm = ""
    @Published var relationshipGoal: RelationshipIntention = .serious_relationship
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func save(userId: UUID) async -> Bool {
        struct UpdateProfile: Encodable {
            let full_name: String
            let date_of_birth: String
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
            full_name: fullName,
            date_of_birth: dateOfBirth,
            gender: gender.rawValue,
            city: city,
            bio: bio,
            job_title: jobTitle,
            company_name: companyName,
            education_level: educationLevel,
            school_name: schoolName,
            height_cm: Int(heightCm),
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
            errorMessage = error.localizedDescription
            return false
        }
    }
}
