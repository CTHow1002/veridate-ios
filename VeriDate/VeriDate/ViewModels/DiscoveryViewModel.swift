import Foundation
import Combine
import Supabase
import PostgREST


enum DiscoverySwipeAction: String {
    case like
    case pass
}

private extension Array where Element == String {
    func removingDuplicateStrings() -> [String] {
        var seen = Set<String>()
        return filter { value in
            seen.insert(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
        }
    }
}

struct CompatibilitySummary: Equatable {
    let score: Int
    let label: String
    let reasons: [String]
}

@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isSavingFilters = false
    @Published var isUndoing = false
    @Published var isLoadingInterestedInYou = false
    @Published var actingProfileIds: Set<UUID> = []
    @Published var lastSwipedProfile: Profile?
    @Published var lastSwipeAction: DiscoverySwipeAction?
    @Published var interestedInYouProfiles: [Profile] = []
    @Published var compatibilitySummaries: [UUID: CompatibilitySummary] = [:]
    @Published var currentProfileInterests: [String] = []
    @Published var profileInterestsById: [UUID: [String]] = [:]

    @Published var preferredGender: GenderType?
    @Published var minAge = 18
    @Published var maxAge = 50
    @Published var preferredCity = ""
    @Published var minDistanceKm = 0
    @Published var maxDistanceKm = 100
    @Published var minHeightCm = 120
    @Published var maxHeightCm = 200
    @Published var educationLevel = ""
    @Published var relationshipGoal: RelationshipIntention?
    @Published var preferredGenders: [String] = []
    @Published var maritalStatuses: [String] = []
    @Published var races: [String] = []
    @Published var religions: [String] = []
    @Published var educationLevels: [String] = []
    @Published var relationshipGoals: [String] = []
    @Published var smokingOptions: [String] = []
    @Published var drinkingOptions: [String] = []
    @Published var exerciseOptions: [String] = []
    @Published var petOptions: [String] = []
    @Published var communicationStyles: [String] = []
    @Published var loveLanguages: [String] = []
    @Published var mbtis: [String] = []
    @Published var languageOptions: [String] = []
    @Published var familyPlansOptions: [String] = []

    private let supabase = SupabaseManager.shared.client
    private var matchChannel: RealtimeChannelV2?
    private var matchListenerTask: Task<Void, Never>?
    let isPremiumUser = false

    var canShowUndo: Bool {
        lastSwipedProfile != nil && lastSwipeAction != nil && !isUndoing
    }

    var interestedInYouCount: Int {
        interestedInYouProfiles.count
    }

    func loadProfiles(userId: UUID, currentProfile: Profile?) async {
        guard currentProfile?.verificationStatus == .verified else {
            profiles = []
            errorMessage = AppLanguageManager.localized("discovery_error_verified_required")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [Profile] = try await supabase
                .rpc("get_discovery_profiles", params: ["requesting_user_id": userId.uuidString])
                .execute()
                .value

            let filteredProfiles = response
                .filter { !$0.isBanned }
                .filter { passesMinimumEducationFilter($0) }
                .filter { passesRelationshipGoalFilter($0) }
                .filter { passesAdvancedFilters($0) }

            let interestContext = await loadInterestHints(currentUserId: userId, candidateProfiles: filteredProfiles)

            let scoredProfiles = filteredProfiles.map { profile in
                (
                    profile: profile,
                    summary: compatibilitySummary(
                        for: profile,
                        currentProfile: currentProfile,
                        currentInterests: interestContext.currentInterests,
                        profileInterests: interestContext.profileInterestsById[profile.id] ?? []
                    )
                )
            }

            compatibilitySummaries = Dictionary(
                uniqueKeysWithValues: scoredProfiles.map { ($0.profile.id, $0.summary) }
            )

            profiles = scoredProfiles
                .sorted { lhs, rhs in
                    if lhs.summary.score == rhs.summary.score {
                        return lhs.profile.id.uuidString < rhs.profile.id.uuidString
                    }

                    return lhs.summary.score > rhs.summary.score
                }
                .map(\.profile)
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("discovery_error_load_profiles_format"), error.localizedDescription)
        }
    }

    func loadFilters(userId: UUID) async {
        struct FilterRow: Decodable {
            let preferred_gender: GenderType?
            let min_age: Int?
            let max_age: Int?
            let preferred_city: String?
            let min_distance_km: Int?
            let max_distance_km: Int?
            let min_height_cm: Int?
            let max_height_cm: Int?
            let education_level: String?
            let relationship_goal: String?
            let preferred_genders: String?
            let marital_statuses: String?
            let races: String?
            let religions: String?
            let education_levels: String?
            let relationship_goals: String?
            let smoking_options: String?
            let drinking_options: String?
            let exercise_options: String?
            let pet_options: String?
            let communication_styles: String?
            let love_languages: String?
            let mbtis: String?
            let language_options: String?
            let family_plans_options: String?
        }

        do {
            let filters: [FilterRow] = try await supabase
                .from("dating_filters")
                .select("preferred_gender,min_age,max_age,preferred_city,min_distance_km,max_distance_km,min_height_cm,max_height_cm,education_level,relationship_goal,preferred_genders,marital_statuses,races,religions,education_levels,relationship_goals,smoking_options,drinking_options,exercise_options,pet_options,communication_styles,love_languages,mbtis,language_options,family_plans_options")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            guard let filter = filters.first else { return }
            preferredGender = filter.preferred_gender
            minAge = filter.min_age ?? minAge
            maxAge = filter.max_age ?? maxAge
            preferredCity = filter.preferred_city ?? ""
            minDistanceKm = filter.min_distance_km ?? minDistanceKm
            maxDistanceKm = filter.max_distance_km ?? maxDistanceKm
            minHeightCm = filter.min_height_cm ?? minHeightCm
            maxHeightCm = filter.max_height_cm ?? maxHeightCm
            let savedEducationValues = splitFilterValues(filter.education_levels)
            let legacyEducationValues = splitFilterValues(filter.education_level)
            let savedRelationshipValues = splitFilterValues(filter.relationship_goals)
            let legacyRelationshipValues = splitFilterValues(filter.relationship_goal)

            educationLevel = legacyEducationValues.first ?? ""
            relationshipGoal = legacyRelationshipValues.compactMap(RelationshipIntention.init(rawValue:)).first
            preferredGenders = splitFilterValues(filter.preferred_genders)
            if preferredGenders.isEmpty, let preferredGender = filter.preferred_gender {
                preferredGenders = [preferredGender.rawValue]
            }
            maritalStatuses = splitFilterValues(filter.marital_statuses)
            races = splitFilterValues(filter.races)
            religions = splitFilterValues(filter.religions)
            educationLevels = savedEducationValues
            if educationLevels.isEmpty, !educationLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                educationLevels = legacyEducationValues
            }
            relationshipGoals = savedRelationshipValues
            if relationshipGoals.isEmpty {
                relationshipGoals = legacyRelationshipValues
            }
            smokingOptions = splitFilterValues(filter.smoking_options)
            drinkingOptions = splitFilterValues(filter.drinking_options)
            exerciseOptions = splitFilterValues(filter.exercise_options)
            petOptions = splitFilterValues(filter.pet_options)
            communicationStyles = splitFilterValues(filter.communication_styles)
            loveLanguages = splitFilterValues(filter.love_languages)
            mbtis = splitFilterValues(filter.mbtis)
            languageOptions = splitFilterValues(filter.language_options)
            familyPlansOptions = splitFilterValues(filter.family_plans_options)
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("discovery_error_load_filters_format"), error.localizedDescription)
        }
    }

    func loadInterestedInYou(userId: UUID) async {
        struct ActionRow: Decodable {
            let actorUserId: UUID
            let targetUserId: UUID
            let action: String

            enum CodingKeys: String, CodingKey {
                case actorUserId = "actor_user_id"
                case targetUserId = "target_user_id"
                case action
            }
        }

        struct MatchRow: Decodable {
            let userOneId: UUID
            let userTwoId: UUID

            enum CodingKeys: String, CodingKey {
                case userOneId = "user_one_id"
                case userTwoId = "user_two_id"
            }
        }

        struct BlockRow: Decodable {
            let blockerUserId: UUID
            let blockedUserId: UUID

            enum CodingKeys: String, CodingKey {
                case blockerUserId = "blocker_user_id"
                case blockedUserId = "blocked_user_id"
            }
        }

        struct LegacyBlockRow: Decodable {
            let blockerUserId: UUID
            let blockedUserId: UUID

            enum CodingKeys: String, CodingKey {
                case blockerUserId = "blocker_id"
                case blockedUserId = "blocked_id"
            }
        }

        isLoadingInterestedInYou = true
        defer { isLoadingInterestedInYou = false }

        do {
            let incomingLikes: [ActionRow] = try await supabase
                .from("profile_actions")
                .select("actor_user_id,target_user_id,action")
                .eq("target_user_id", value: userId)
                .eq("action", value: DiscoverySwipeAction.like.rawValue)
                .execute()
                .value

            let ownActions: [ActionRow] = try await supabase
                .from("profile_actions")
                .select("actor_user_id,target_user_id,action")
                .eq("actor_user_id", value: userId)
                .execute()
                .value

            let matches: [MatchRow] = try await supabase
                .from("matches")
                .select("user_one_id,user_two_id")
                .or("user_one_id.eq.\(userId.uuidString),user_two_id.eq.\(userId.uuidString)")
                .execute()
                .value

            let blocks: [BlockRow] = try await supabase
                .from("blocks")
                .select("blocker_user_id,blocked_user_id")
                .or("blocker_user_id.eq.\(userId.uuidString),blocked_user_id.eq.\(userId.uuidString)")
                .execute()
                .value
            let legacyBlocks: [BlockRow] = (try? await supabase
                .from("user_blocks")
                .select("blocker_user_id,blocked_user_id")
                .or("blocker_user_id.eq.\(userId.uuidString),blocked_user_id.eq.\(userId.uuidString)")
                .execute()
                .value) ?? []
            let oldBlocks: [LegacyBlockRow] = (try? await supabase
                .from("blocks")
                .select("blocker_id,blocked_id")
                .or("blocker_id.eq.\(userId.uuidString),blocked_id.eq.\(userId.uuidString)")
                .execute()
                .value) ?? []

            let alreadyActionedIds = Set(ownActions.map(\.targetUserId))
            let matchedIds = Set(matches.map { $0.userOneId == userId ? $0.userTwoId : $0.userOneId })
            let blockedIds = Set((blocks + legacyBlocks).map { $0.blockerUserId == userId ? $0.blockedUserId : $0.blockerUserId })
                .union(oldBlocks.map { $0.blockerUserId == userId ? $0.blockedUserId : $0.blockerUserId })

            let interestedIds = incomingLikes
                .map(\.actorUserId)
                .filter { $0 != userId }
                .filter { !alreadyActionedIds.contains($0) }
                .filter { !matchedIds.contains($0) }
                .filter { !blockedIds.contains($0) }

            var loadedProfiles: [Profile] = []
            for id in Array(Set(interestedIds)).prefix(25) {
                if let profile = try await fetchProfile(userId: id), !profile.isBanned {
                    loadedProfiles.append(profile)
                }
            }

            interestedInYouProfiles = loadedProfiles
        } catch {
            interestedInYouProfiles = []
        }
    }

    func saveFilters(userId: UUID) async -> Bool {
        struct FilterPayload: Encodable {
            let user_id: UUID
            let preferred_gender: String?
            let min_age: Int
            let max_age: Int
            let preferred_city: String?
            let min_distance_km: Int
            let max_distance_km: Int
            let min_height_cm: Int
            let max_height_cm: Int
            let education_level: String?
            let relationship_goal: String?
            let preferred_genders: String?
            let marital_statuses: String?
            let races: String?
            let religions: String?
            let education_levels: String?
            let relationship_goals: String?
            let smoking_options: String?
            let drinking_options: String?
            let exercise_options: String?
            let pet_options: String?
            let communication_styles: String?
            let love_languages: String?
            let mbtis: String?
            let language_options: String?
            let family_plans_options: String?
            let verified_only: Bool
            let updated_at: String

            enum CodingKeys: String, CodingKey {
                case user_id
                case preferred_gender
                case min_age
                case max_age
                case preferred_city
                case min_distance_km
                case max_distance_km
                case min_height_cm
                case max_height_cm
                case education_level
                case relationship_goal
                case preferred_genders
                case marital_statuses
                case races
                case religions
                case education_levels
                case relationship_goals
                case smoking_options
                case drinking_options
                case exercise_options
                case pet_options
                case communication_styles
                case love_languages
                case mbtis
                case language_options
                case family_plans_options
                case verified_only
                case updated_at
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)

                try container.encode(user_id, forKey: .user_id)
                try container.encode(min_age, forKey: .min_age)
                try container.encode(max_age, forKey: .max_age)
                try container.encode(min_distance_km, forKey: .min_distance_km)
                try container.encode(max_distance_km, forKey: .max_distance_km)
                try container.encode(min_height_cm, forKey: .min_height_cm)
                try container.encode(max_height_cm, forKey: .max_height_cm)
                try container.encode(verified_only, forKey: .verified_only)
                try container.encode(updated_at, forKey: .updated_at)

                if let preferred_gender {
                    try container.encode(preferred_gender, forKey: .preferred_gender)
                } else {
                    try container.encodeNil(forKey: .preferred_gender)
                }

                if let preferred_city {
                    try container.encode(preferred_city, forKey: .preferred_city)
                } else {
                    try container.encodeNil(forKey: .preferred_city)
                }

                if let education_level {
                    try container.encode(education_level, forKey: .education_level)
                } else {
                    try container.encodeNil(forKey: .education_level)
                }

                if let relationship_goal {
                    try container.encode(relationship_goal, forKey: .relationship_goal)
                } else {
                    try container.encodeNil(forKey: .relationship_goal)
                }

                try container.encode(preferred_genders, forKey: .preferred_genders)
                try container.encode(marital_statuses, forKey: .marital_statuses)
                try container.encode(races, forKey: .races)
                try container.encode(religions, forKey: .religions)
                try container.encode(education_levels, forKey: .education_levels)
                try container.encode(relationship_goals, forKey: .relationship_goals)
                try container.encode(smoking_options, forKey: .smoking_options)
                try container.encode(drinking_options, forKey: .drinking_options)
                try container.encode(exercise_options, forKey: .exercise_options)
                try container.encode(pet_options, forKey: .pet_options)
                try container.encode(communication_styles, forKey: .communication_styles)
                try container.encode(love_languages, forKey: .love_languages)
                try container.encode(mbtis, forKey: .mbtis)
                try container.encode(language_options, forKey: .language_options)
                try container.encode(family_plans_options, forKey: .family_plans_options)
            }
        }

        isSavingFilters = true
        errorMessage = nil
        defer { isSavingFilters = false }

        do {
            try await supabase
                .from("dating_filters")
                .upsert(
                    FilterPayload(
                        user_id: userId,
                        preferred_gender: preferredGenders.first ?? preferredGender?.rawValue,
                        min_age: min(minAge, maxAge),
                        max_age: max(minAge, maxAge),
                        preferred_city: trimmedOrNil(preferredCity),
                        min_distance_km: min(minDistanceKm, maxDistanceKm),
                        max_distance_km: max(minDistanceKm, maxDistanceKm),
                        min_height_cm: min(minHeightCm, maxHeightCm),
                        max_height_cm: max(minHeightCm, maxHeightCm),
                        education_level: educationLevels.first,
                        relationship_goal: relationshipGoals.first,
                        preferred_genders: joinedFilterValues(preferredGenders),
                        marital_statuses: joinedFilterValues(maritalStatuses),
                        races: joinedFilterValues(races),
                        religions: joinedFilterValues(religions),
                        education_levels: joinedFilterValues(educationLevels),
                        relationship_goals: joinedFilterValues(relationshipGoals),
                        smoking_options: joinedFilterValues(smokingOptions),
                        drinking_options: joinedFilterValues(drinkingOptions),
                        exercise_options: joinedFilterValues(exerciseOptions),
                        pet_options: joinedFilterValues(petOptions),
                        communication_styles: joinedFilterValues(communicationStyles),
                        love_languages: joinedFilterValues(loveLanguages),
                        mbtis: joinedFilterValues(mbtis),
                        language_options: joinedFilterValues(languageOptions),
                        family_plans_options: joinedFilterValues(familyPlansOptions),
                        verified_only: true,
                        updated_at: ISO8601DateFormatter().string(from: Date())
                    ),
                    onConflict: "user_id"
                )
                .execute()

            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("discovery_error_save_filters_format"), error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func like(userId: UUID, targetUserId: UUID) async -> Bool {
        await action(userId: userId, targetUserId: targetUserId, action: .like)
    }

    @discardableResult
    func pass(userId: UUID, targetUserId: UUID) async -> Bool {
        await action(userId: userId, targetUserId: targetUserId, action: .pass)
    }

    @discardableResult
    private func action(userId: UUID, targetUserId: UUID, action: DiscoverySwipeAction) async -> Bool {
        struct ActionPayload: Encodable {
            let actor_user_id: UUID
            let target_user_id: UUID
            let action: String
            let created_at: String
        }

        guard let swipedIndex = profiles.firstIndex(where: { $0.id == targetUserId }) else {
            return false
        }

        let swipedProfile = profiles[swipedIndex]
        actingProfileIds.insert(targetUserId)
        errorMessage = nil
        defer { actingProfileIds.remove(targetUserId) }

        profiles.remove(at: swipedIndex)

        do {
            try await supabase
                .from("profile_actions")
                .upsert(
                    ActionPayload(
                        actor_user_id: userId,
                        target_user_id: targetUserId,
                        action: action.rawValue,
                        created_at: ISO8601DateFormatter().string(from: Date())
                    ),
                    onConflict: "actor_user_id,target_user_id"
                )
                .execute()

            lastSwipedProfile = swipedProfile
            lastSwipeAction = action
            profiles.removeAll { $0.id == targetUserId }
            return true
        } catch {
            profiles.insert(swipedProfile, at: min(swipedIndex, profiles.count))
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("discovery_error_save_action_format"), localizedSwipeAction(action), error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func undoLastSwipe(userId: UUID) async -> Bool {
        guard let profile = lastSwipedProfile else {
            return false
        }

        isUndoing = true
        errorMessage = nil
        defer { isUndoing = false }

        do {
            try await supabase
                .from("profile_actions")
                .delete()
                .eq("actor_user_id", value: userId)
                .eq("target_user_id", value: profile.id)
                .execute()

            profiles.removeAll { $0.id == profile.id }
            profiles.insert(profile, at: 0)
            lastSwipedProfile = nil
            lastSwipeAction = nil
            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("discovery_error_undo_swipe_format"), error.localizedDescription)
            return false
        }
    }

    func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
    }

    func compatibilitySummary(for profile: Profile) -> CompatibilitySummary? {
        compatibilitySummaries[profile.id]
    }

    func sharedInterestHighlights(for profile: Profile) -> [String] {
        let current = Set(currentProfileInterests.map(normalizeFilterValue).filter { !$0.isEmpty })
        guard !current.isEmpty else { return [] }

        return (profileInterestsById[profile.id] ?? [])
            .filter { current.contains(normalizeFilterValue($0)) }
            .removingDuplicateStrings()
            .prefix(2)
            .map { $0 }
    }

    private func loadInterestHints(currentUserId: UUID, candidateProfiles: [Profile]) async -> (currentInterests: [String], profileInterestsById: [UUID: [String]]) {
        do {
            let currentInterests = try await ProfileInterestService.shared.loadProfileInterests(userId: currentUserId)
            var interestsByProfile: [UUID: [String]] = [:]

            for profile in candidateProfiles.prefix(80) {
                interestsByProfile[profile.id] = (try? await ProfileInterestService.shared.loadProfileInterests(userId: profile.id)) ?? []
            }

            currentProfileInterests = currentInterests
            profileInterestsById = interestsByProfile
            return (currentInterests, interestsByProfile)
        } catch {
            currentProfileInterests = []
            profileInterestsById = [:]
            return ([], [:])
        }
    }

    private func compatibilitySummary(
        for profile: Profile,
        currentProfile: Profile?,
        currentInterests: [String],
        profileInterests: [String]
    ) -> CompatibilitySummary {
        var score = 36
        var reasons: [String] = []

        if let currentProfile,
           let currentGoal = currentProfile.relationshipGoal,
           let profileGoal = profile.relationshipGoal {
            if currentGoal == profileGoal {
                score += 16
                reasons.append(AppLanguageManager.localized("compatibility_reason_same_relationship_intention"))
            } else if relationshipGoalsAreCompatible(currentGoal, profileGoal) {
                score += 8
            } else {
                score -= 6
            }
        }

        if passesMinimumEducationFilter(profile) {
            score += 5
            if profile.educationLevel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                reasons.append(AppLanguageManager.localized("compatibility_reason_education_preference_fits"))
            }
        }

        if passesRelationshipGoalFilter(profile), relationshipGoal != nil {
            score += 5
        }

        if profile.verificationStatus == .verified {
            score += 8
            reasons.append(AppLanguageManager.localized("compatibility_reason_verified_profile"))
        }

        if let distance = distanceFromCurrentUser(to: profile) {
            switch distance {
            case ...10:
                score += 10
                reasons.append(AppLanguageManager.localized("compatibility_reason_nearby"))
            case ...30:
                score += 6
                reasons.append(AppLanguageManager.localized("compatibility_reason_comfortable_distance"))
            case ...max(30, Double(maxDistanceKm)):
                score += 2
            default:
                score -= 8
            }
        }

        if hasCompleteCoreProfile(profile) {
            score += 5
            reasons.append(AppLanguageManager.localized("compatibility_reason_complete_profile"))
        }

        if profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 2
        }

        let sharedInterests = sharedValues(currentInterests, profileInterests)
        if !sharedInterests.isEmpty {
            score += min(16, 6 + (sharedInterests.count - 1) * 3)
            reasons.append(AppLanguageManager.localized("compatibility_reason_shared_interests"))
        }

        if let currentProfile {
            score += lifestyleCompatibilityScore(currentProfile: currentProfile, profile: profile, reasons: &reasons)
        }

        let preferenceScore = selectedPreferenceCompatibilityScore(profile)
        score += preferenceScore

        if preferenceScore >= 8 {
            reasons.append(AppLanguageManager.localized("compatibility_reason_matches_preferences"))
        }

        let clampedScore = min(max(score, 0), 99)
        return CompatibilitySummary(
            score: clampedScore,
            label: compatibilityLabel(for: clampedScore),
            reasons: Array(reasons.prefix(3))
        )
    }

    private func compatibilityLabel(for score: Int) -> String {
        switch score {
        case 85...:
            return AppLanguageManager.localized("compatibility_label_strong_match")
        case 70..<85:
            return AppLanguageManager.localized("compatibility_label_good_match")
        case 55..<70:
            return AppLanguageManager.localized("compatibility_label_possible_match")
        default:
            return AppLanguageManager.localized("compatibility_label_explore_slowly")
        }
    }

    private func relationshipGoalsAreCompatible(_ lhs: RelationshipIntention, _ rhs: RelationshipIntention) -> Bool {
        if lhs == .not_sure || rhs == .not_sure {
            return true
        }

        let committed: Set<RelationshipIntention> = [.serious_relationship, .marriage]
        return committed.contains(lhs) && committed.contains(rhs)
    }

    private func lifestyleCompatibilityScore(currentProfile: Profile, profile: Profile, reasons: inout [String]) -> Int {
        var score = 0
        var lifestyleMatches = 0

        if normalizedValuesOverlap(currentProfile.languages, profile.languages) {
            score += 8
            reasons.append(AppLanguageManager.localized("compatibility_reason_shared_language"))
        }

        if sameNonEmptyValue(currentProfile.familyPlans, profile.familyPlans) {
            score += 6
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.communicationStyle, profile.communicationStyle) {
            score += 5
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.loveLanguage, profile.loveLanguage) {
            score += 5
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.exercise, profile.exercise) {
            score += 4
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.smoking, profile.smoking) {
            score += 3
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.drinking, profile.drinking) {
            score += 3
            lifestyleMatches += 1
        }

        if normalizedValuesOverlap(currentProfile.pets, profile.pets) {
            score += 3
            lifestyleMatches += 1
        }

        if sameNonEmptyValue(currentProfile.mbti, profile.mbti) {
            score += 2
            lifestyleMatches += 1
        }

        if currentProfile.horoscope == profile.horoscope, currentProfile.horoscope != nil {
            score += 2
        }

        if sameNonEmptyValue(currentProfile.religion, profile.religion) {
            score += 3
        }

        if sameNonEmptyValue(currentProfile.currentlyLiving, profile.currentlyLiving) || sameNonEmptyValue(currentProfile.city, profile.city) {
            score += 3
        }

        if lifestyleMatches >= 3 {
            reasons.append(AppLanguageManager.localized("compatibility_reason_lifestyle_alignment"))
        }

        return min(score, 28)
    }

    private func selectedPreferenceCompatibilityScore(_ profile: Profile) -> Int {
        var score = 0
        score += selectedMatchScore(preferredGenders, value: profile.gender?.rawValue, points: 4)
        score += selectedMatchScore(maritalStatuses, value: profile.maritalStatus?.rawValue, points: 3)
        score += selectedMatchScore(races, value: profile.race, points: 2)
        score += selectedMatchScore(religions, value: profile.religion, points: 3)
        score += selectedMatchScore(educationLevels, value: profile.educationLevel, points: 3)
        score += selectedMatchScore(relationshipGoals, value: profile.relationshipGoal?.rawValue, points: 5)
        score += selectedMatchScore(smokingOptions, value: profile.smoking, points: 2)
        score += selectedMatchScore(drinkingOptions, value: profile.drinking, points: 2)
        score += selectedMatchScore(exerciseOptions, value: profile.exercise, points: 2)
        score += selectedMatchScore(petOptions, value: profile.pets, points: 2, isMultiValue: true)
        score += selectedMatchScore(communicationStyles, value: profile.communicationStyle, points: 3)
        score += selectedMatchScore(loveLanguages, value: profile.loveLanguage, points: 3)
        score += selectedMatchScore(mbtis, value: profile.mbti, points: 1)
        score += selectedMatchScore(languageOptions, value: profile.languages, points: 4, isMultiValue: true)
        score += selectedMatchScore(familyPlansOptions, value: profile.familyPlans, points: 4)
        return min(score, 18)
    }

    private func selectedMatchScore(_ selectedValues: [String], value: String?, points: Int, isMultiValue: Bool = false) -> Int {
        let cleanedSelected = Set(selectedValues.map(normalizeFilterValue).filter { !$0.isEmpty })
        guard !cleanedSelected.isEmpty else { return 0 }

        let profileValues = isMultiValue
            ? Set(splitFilterValues(value).map(normalizeFilterValue).filter { !$0.isEmpty })
            : Set([value.map(normalizeFilterValue) ?? ""].filter { !$0.isEmpty })
        guard !profileValues.isEmpty else { return 0 }

        let matches = !cleanedSelected.isDisjoint(with: profileValues)
        return matches ? points : 0
    }

    private func sharedValues(_ lhs: [String], _ rhs: [String]) -> [String] {
        let rhsValues = Set(rhs.map(normalizeFilterValue).filter { !$0.isEmpty })
        guard !rhsValues.isEmpty else { return [] }

        return lhs
            .filter { rhsValues.contains(normalizeFilterValue($0)) }
            .removingDuplicateStrings()
    }

    private func normalizedValuesOverlap(_ lhs: String?, _ rhs: String?) -> Bool {
        let lhsValues = Set(splitFilterValues(lhs).map(normalizeFilterValue).filter { !$0.isEmpty })
        let rhsValues = Set(splitFilterValues(rhs).map(normalizeFilterValue).filter { !$0.isEmpty })
        return !lhsValues.isEmpty && !rhsValues.isEmpty && !lhsValues.isDisjoint(with: rhsValues)
    }

    private func sameNonEmptyValue(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let normalizedLHS = normalizeFilterValue(lhs)
        let normalizedRHS = normalizeFilterValue(rhs)
        return !normalizedLHS.isEmpty && normalizedLHS == normalizedRHS
    }

    private func hasCompleteCoreProfile(_ profile: Profile) -> Bool {
        let hasName = profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasBio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasWork = profile.jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || profile.companyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasEducation = profile.educationLevel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || profile.schoolName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasGoal = profile.relationshipGoal != nil

        return hasName && hasBio && hasWork && hasEducation && hasGoal
    }

    private func distanceFromCurrentUser(to profile: Profile) -> Double? {
        // Placeholder until the app has a centralized location-distance helper available in the view model layer.
        // Current distance filtering is handled by the Supabase discovery RPC.
        nil
    }

    private func localizedSwipeAction(_ action: DiscoverySwipeAction) -> String {
        switch action {
        case .like:
            return AppLanguageManager.localized("discovery_action_like")
        case .pass:
            return AppLanguageManager.localized("discovery_action_pass")
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func joinedFilterValues(_ values: [String]) -> String? {
        let cleanedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return cleanedValues.isEmpty ? nil : cleanedValues.joined(separator: ",")
    }

    private func splitFilterValues(_ value: String?) -> [String] {
        value?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func passesAdvancedFilters(_ profile: Profile) -> Bool {
        matchesAny(preferredGenders, value: profile.gender?.rawValue)
            && matchesAny(maritalStatuses, value: profile.maritalStatus?.rawValue)
            && matchesAny(races, value: profile.race)
            && matchesAny(religions, value: profile.religion)
            && matchesAny(educationLevels, value: profile.educationLevel)
            && matchesAny(relationshipGoals, value: profile.relationshipGoal?.rawValue)
            && matchesAny(smokingOptions, value: profile.smoking)
            && matchesAny(drinkingOptions, value: profile.drinking)
            && matchesAny(exerciseOptions, value: profile.exercise)
            && matchesMultiValueAny(petOptions, value: profile.pets)
            && matchesAny(communicationStyles, value: profile.communicationStyle)
            && matchesAny(loveLanguages, value: profile.loveLanguage)
            && matchesAny(mbtis, value: profile.mbti)
            && matchesMultiValueAny(languageOptions, value: profile.languages)
            && matchesAny(familyPlansOptions, value: profile.familyPlans)
    }

    private func matchesAny(_ selectedValues: [String], value: String?) -> Bool {
        let cleanedSelected = selectedValues.map(normalizeFilterValue).filter { !$0.isEmpty }
        guard !cleanedSelected.isEmpty else { return true }
        guard let value else { return true }
        return cleanedSelected.contains(normalizeFilterValue(value))
    }

    private func matchesMultiValueAny(_ selectedValues: [String], value: String?) -> Bool {
        let cleanedSelected = Set(selectedValues.map(normalizeFilterValue).filter { !$0.isEmpty })
        guard !cleanedSelected.isEmpty else { return true }
        guard let value else { return true }

        let profileValues = Set(splitFilterValues(value).map(normalizeFilterValue))
        guard !profileValues.isEmpty else { return true }
        return !cleanedSelected.isDisjoint(with: profileValues)
    }

    private func normalizeFilterValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    private func passesMinimumEducationFilter(_ profile: Profile) -> Bool {
        let selectedMinimum = educationLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedMinimum.isEmpty else { return true }

        guard let profileEducation = profile.educationLevel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profileEducation.isEmpty else {
            // Missing education should not hide otherwise valid profiles.
            return true
        }

        return educationRank(profileEducation) >= educationRank(selectedMinimum)
    }

    private func fetchProfile(userId: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        return profiles.first
    }

    private func passesRelationshipGoalFilter(_ profile: Profile) -> Bool {
        guard let selectedGoal = relationshipGoal else { return true }

        guard let profileGoal = profile.relationshipGoal else {
            // Missing relationship goal should not hide otherwise valid profiles.
            return true
        }

        return profileGoal == selectedGoal
    }

    private func educationRank(_ level: String) -> Int {
        let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let rankMap: [String: Int] = [
            "primary": 0,
            "primary school": 0,
            "secondary": 1,
            "secondary school": 1,
            "high school": 1,
            "spm": 1,
            "diploma": 2,
            "advanced diploma": 2,
            "degree": 3,
            "bachelor": 3,
            "bachelor's degree": 3,
            "bachelors degree": 3,
            "master": 4,
            "master's degree": 4,
            "masters degree": 4,
            "phd": 5,
            "doctorate": 5
        ]

        if let exactRank = rankMap[normalized] {
            return exactRank
        }

        if normalized.contains("phd") || normalized.contains("doctorate") {
            return 5
        }

        if normalized.contains("master") {
            return 4
        }

        if normalized.contains("degree") || normalized.contains("bachelor") {
            return 3
        }

        if normalized.contains("diploma") {
            return 2
        }

        if normalized.contains("secondary") || normalized.contains("high school") || normalized.contains("spm") {
            return 1
        }

        if normalized.contains("primary") {
            return 0
        }

        return 0
    }

    func subscribeToMatches(userId: UUID, onMatch: @escaping (UUID, UUID) -> Void) async {
        matchListenerTask?.cancel()
        if let matchChannel {
            await supabase.removeChannel(matchChannel)
        }

        let channel = supabase.channel("matches-listener-\(userId.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "matches"
        )

        matchListenerTask = Task { [weak self] in
            for await insertion in insertions {
                guard !Task.isCancelled else { return }

                let record = insertion.record
                guard
                    let matchIdText = record["id"]?.stringValue,
                    let matchId = UUID(uuidString: matchIdText),
                    let userOne = record["user_one_id"]?.stringValue,
                    let userTwo = record["user_two_id"]?.stringValue
                else { continue }

                if userOne == userId.uuidString, let other = UUID(uuidString: userTwo) {
                    await MainActor.run {
                        onMatch(matchId, other)
                    }
                } else if userTwo == userId.uuidString, let other = UUID(uuidString: userOne) {
                    await MainActor.run {
                        onMatch(matchId, other)
                    }
                }
            }

            _ = self
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("Failed to subscribe to matches channel:", error.localizedDescription)
        }
        matchChannel = channel
    }
}
