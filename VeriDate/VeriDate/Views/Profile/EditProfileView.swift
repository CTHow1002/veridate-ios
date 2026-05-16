import SwiftUI
import Foundation
import PhotosUI
import PostgREST
import Supabase
import UIKit
import UniformTypeIdentifiers

struct EditProfileView: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var displayName = ""
    @State private var originalDisplayName = ""
    @State private var displayNameChangedAt: Date?
    @State private var displayNameChangedAtStorageValue: String?
    @State private var dateOfBirth = Date()
    @State private var gender: GenderType = .male
    @State private var race = ""
    @State private var religion = ""
    @State private var hometown = ""
    @State private var currentlyLiving = ""
    @State private var showingHometownSelector = false
    @State private var showingCurrentlyLivingSelector = false
    @State private var bio = ""
    @State private var jobTitle = ""
    @State private var companyName = ""
    @State private var educationLevel = ProfileSetupViewModel.educationLevels.first ?? "Secondary"
    @State private var schoolName = ""
    @State private var heightCm = 170
    @State private var relationshipGoal: RelationshipIntention = .serious_relationship
    @State private var genderInterest: GenderInterest = .opposite_gender
    @State private var maritalStatus: MaritalStatus = .single
    @State private var smoking = ""
    @State private var drinking = ""
    @State private var exercise = ""
    @State private var pets = ""
    @State private var communicationStyle = ""
    @State private var loveLanguage = ""
    @State private var mbti = ""
    @State private var languages = ""
    @State private var familyPlans = ""
    @State private var photos: [ProfilePhoto] = []
    @State private var primaryPhotoUpdateInProgressId: UUID?
    @State private var photoReorderInProgress = false
    @State private var photoMutationRevision = 0
    @State private var photoPendingDeletion: ProfilePhoto?
    @State private var prompts: [ProfilePrompt] = []
    @State private var interests: [String] = []
    @State private var interestMessage: String?
    @State private var changeRequestKind: ProfileChangeRequestKind?

    @State private var isSaving = false
    @State private var isSubmittingChangeRequest = false
    @State private var errorMessage: String?

    private let supabase = SupabaseManager.shared.client
    private let smokingOptions = ["", "Never", "Socially", "Sometimes", "Often", "Prefer not to say"]
    private let drinkingOptions = ["", "Never", "Socially", "Sometimes", "Often", "Prefer not to say"]
    private let exerciseOptions = ["", "Daily", "A few times a week", "Sometimes", "Rarely", "Prefer not to say"]
    private let raceOptions = ["", "Malay", "Chinese", "Indian", "Iban", "Kadazan", "Mixed", "Other", "Prefer not to say"]
    private let religionOptions = ["", "Islam", "Buddhism", "Christianity", "Hinduism", "Taoism", "Atheist", "Agnostic", "Spiritual", "Other", "Prefer not to say"]
    private let petOptions = ["Dog", "Cat", "Fish", "Bird", "Rabbit", "Hamster", "Reptile", "Have pets", "Want pets", "No pet but love them", "Not a pet person", "Allergic to pets", "Prefer not to say"]
    private let communicationStyleOptions = ["", "Responsive texter", "Thoughtful texter", "Phone calls", "Video calls", "Voice messages", "In-person conversations", "Plans ahead", "Spontaneous check-ins", "Low-maintenance communicator"]
    private let loveLanguageOptions = ["", "Quality time", "Words of affirmation", "Acts of service", "Physical touch", "Receiving gifts", "Not sure yet"]
    private let mbtiOptions = ["", "ISTJ", "ISFJ", "INFJ", "INTJ", "ISTP", "ISFP", "INFP", "INTP", "ESTP", "ESFP", "ENFP", "ENTP", "ESTJ", "ESFJ", "ENFJ", "ENTJ", "NOT SURE"]
    private let familyPlansOptions = ["", "Want children", "Open to children", "Do not want children", "Have children", "Prefer not to say"]
    private let languageOptions = ["English", "Malay", "Mandarin", "Cantonese", "Tamil", "Hokkien", "Hakka", "Teochew", "Japanese", "Korean", "Arabic", "Hindi", "Indonesian", "Thai", "Other"]
    private let birthDateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let now = Date()
        let oldest = calendar.date(byAdding: .year, value: -80, to: now) ?? now
        let youngest = calendar.date(byAdding: .year, value: -18, to: now) ?? now
        return oldest...youngest
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    EditProfileGuidanceCard()
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.photos.title"),
                        subtitle: AppLanguageManager.localized("editProfile.photos.subtitle")
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(AppLanguageManager.localized("editProfile.photos.guidanceTitle"))
                                        .font(.subheadline.weight(.semibold))

                                    Text(AppLanguageManager.localized("editProfile.photos.guidanceMessage"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("\(validPhotos.count)/6")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            }

                            ProfilePhotoSlotsView(
                                photos: validPhotos,
                                userId: session.currentUserId,
                                primaryPhotoUpdateInProgressId: primaryPhotoUpdateInProgressId,
                                photoReorderInProgress: photoReorderInProgress,
                                onUploadCompleted: { uploadedPhoto in
                                    await handleUploadedPhoto(uploadedPhoto)
                                },
                                onSaveOrder: { orderedPhotos in
                                    Task {
                                        await savePhotoOrder(orderedPhotos)
                                    }
                                },
                                onDelete: { photo in
                                    photoPendingDeletion = photo
                                }
                            )

                            PhotoCompletionHint(photoCount: validPhotos.count)

                            if validPhotos.isEmpty {
                                EmptyProfilePhotosView()
                            }
                        }
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.basicIdentity.title"),
                        subtitle: AppLanguageManager.localized("editProfile.basicIdentity.subtitle")
                    ) {
                        LockedVerifiedFieldRow(
                            title: AppLanguageManager.localized("profileSetup.name.fullNamePlaceholder"),
                            value: fullName.isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : fullName,
                            reason: AppLanguageManager.localized("editProfile.basicIdentity.legalNamePrivateReason")
                        )

                        VerifiedChangeRequestButton(
                            title: AppLanguageManager.localized("editProfile.basicIdentity.requestLegalNameUpdate"),
                            systemImage: "person.text.rectangle"
                        ) {
                            changeRequestKind = .legalName
                        }

                        displayNameEditor

                        InlineCompletionHint(
                            isComplete: !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            completeText: AppLanguageManager.localized("editProfile.basicIdentity.displayNameComplete"),
                            incompleteText: AppLanguageManager.localized("editProfile.basicIdentity.displayNameIncomplete")
                        )

                        DatePicker(
                            AppLanguageManager.localized("profileSetup.basics.dateOfBirth"),
                            selection: $dateOfBirth,
                            in: birthDateRange,
                            displayedComponents: .date
                        )

                        EditProfileOptionMenuField(
                            title: AppLanguageManager.localized("profileSetup.basics.gender"),
                            selection: $gender,
                            options: GenderType.allCases.map { gender in
                                EditProfileOption(value: gender, title: LocalizedProfileDisplay.gender(gender))
                            }
                        )

                        EditProfileOptionMenuField(
                            title: AppLanguageManager.localized("profileSetup.moreDetails.maritalStatus"),
                            selection: $maritalStatus,
                            options: MaritalStatus.allCases.map { status in
                                EditProfileOption(value: status, title: status.title)
                            }
                        )

                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.race"), selection: $race, options: raceOptions)
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.religion"), selection: $religion, options: religionOptions)

                        EditProfileOptionMenuField(
                            title: AppLanguageManager.localized("profileSetup.basics.height"),
                            selection: $heightCm,
                            options: (120...220).map { height in
                                EditProfileOption(value: height, title: "\(height) cm")
                            },
                            usesWheelPicker: true
                        )

                        TextField(AppLanguageManager.localized("profileSetup.bio.title"), text: $bio, axis: .vertical)
                            .lineLimit(3...6)

                        InlineCompletionHint(
                            isComplete: !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            completeText: AppLanguageManager.localized("editProfile.basicIdentity.bioComplete"),
                            incompleteText: AppLanguageManager.localized("editProfile.basicIdentity.bioIncomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.datingIntention.title"),
                        subtitle: AppLanguageManager.localized("editProfile.datingIntention.subtitle")
                    ) {
                        EditProfileOptionMenuField(
                            title: AppLanguageManager.localized("profileSetup.intentions.lookingFor"),
                            selection: $relationshipGoal,
                            options: RelationshipIntention.allCases.map { goal in
                                EditProfileOption(value: goal, title: LocalizedProfileDisplay.relationshipGoal(goal))
                            }
                        )

                        EditProfileOptionMenuField(
                            title: AppLanguageManager.localized("profileSetup.intentions.interestedIn"),
                            selection: $genderInterest,
                            options: GenderInterest.allCases.map { option in
                                EditProfileOption(value: option, title: option.title)
                            }
                        )

                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.familyPlans"), selection: $familyPlans, options: familyPlansOptions)

                        InlineCompletionHint(
                            isComplete: true,
                            completeText: AppLanguageManager.localized("editProfile.datingIntention.hint.complete"),
                            incompleteText: AppLanguageManager.localized("editProfile.datingIntention.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.lifestyle.title"),
                        subtitle: AppLanguageManager.localized("editProfile.lifestyle.subtitle")
                    ) {
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.smoking"), selection: $smoking, options: smokingOptions)
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.drinking"), selection: $drinking, options: drinkingOptions)
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.exercise"), selection: $exercise, options: exerciseOptions)
                        EditProfileMultiSelectField(
                            title: AppLanguageManager.localized("profileSetup.moreDetails.pets"),
                            selectionText: $pets,
                            options: petOptions,
                            maxSelection: 4
                        )
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.communicationStyle"), selection: $communicationStyle, options: communicationStyleOptions)
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.loveLanguage"), selection: $loveLanguage, options: loveLanguageOptions)
                        EditProfileStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.mbti"), selection: $mbti, options: mbtiOptions)

                        EditProfileReadonlyField(
                            title: AppLanguageManager.localized("profile.preview.horoscope"),
                            value: horoscopeText
                        )

                        EditProfileMultiSelectField(
                            title: AppLanguageManager.localized("profileSetup.moreDetails.languages"),
                            selectionText: $languages,
                            options: languageOptions,
                            maxSelection: 6,
                            displayTitle: { LocalizedProfileDisplay.language($0) }
                        )

                        InlineCompletionHint(
                            isComplete: lifestyleCompletionCount >= 3,
                            completeText: AppLanguageManager.localized("editProfile.lifestyle.hint.complete"),
                            incompleteText: AppLanguageManager.localized("editProfile.lifestyle.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.location.title"),
                        subtitle: AppLanguageManager.localized("editProfile.location.subtitle")
                    ) {
                        EditProfileMapCityRow(
                            title: AppLanguageManager.localized("editProfile.location.hometown"),
                            value: hometown,
                            actionTitle: AppLanguageManager.localized("editProfile.location.searchHometown"),
                            onSearch: {
                                showingHometownSelector = true
                            }
                        )

                        EditProfileMapCityRow(
                            title: AppLanguageManager.localized("editProfile.location.currentlyLiving"),
                            value: currentlyLiving,
                            actionTitle: AppLanguageManager.localized("editProfile.location.searchCurrentCity"),
                            onSearch: {
                                showingCurrentlyLivingSelector = true
                            }
                        )

                        InlineCompletionHint(
                            isComplete: !currentlyLiving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            completeText: AppLanguageManager.localized("editProfile.location.hint.complete"),
                            incompleteText: AppLanguageManager.localized("editProfile.location.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.work.title"),
                        subtitle: AppLanguageManager.localized("editProfile.work.subtitle")
                    ) {
                        LockedVerifiedFieldRow(
                            title: AppLanguageManager.localized("editProfile.work.jobTitle"),
                            value: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : localizedJobTitle,
                            reason: AppLanguageManager.localized("editProfile.work.jobTitle.reason")
                        )

                        LockedVerifiedFieldRow(
                            title: AppLanguageManager.localized("editProfile.work.company"),
                            value: isNonWorkingStatus ? AppLanguageManager.localized("editProfile.common.notApplicable") : (companyName.isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : companyName),
                            reason: AppLanguageManager.localized("editProfile.verified.changeRequest.reason")
                        )

                        VerifiedChangeRequestButton(
                            title: AppLanguageManager.localized("editProfile.work.requestUpdate"),
                            systemImage: "briefcase.fill"
                        ) {
                            changeRequestKind = .work
                        }

                        InlineCompletionHint(
                            isComplete: !jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            completeText: AppLanguageManager.localized("editProfile.work.hint.complete"),
                            incompleteText: AppLanguageManager.localized("editProfile.work.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.education.title"),
                        subtitle: AppLanguageManager.localized("editProfile.education.subtitle")
                    ) {
                        LockedVerifiedFieldRow(
                            title: AppLanguageManager.localized("editProfile.education.level"),
                            value: educationLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : LocalizedProfileDisplay.option(educationLevel),
                            reason: AppLanguageManager.localized("editProfile.education.level.reason")
                        )

                        LockedVerifiedFieldRow(
                            title: AppLanguageManager.localized("editProfile.education.school"),
                            value: schoolName.isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : schoolName,
                            reason: AppLanguageManager.localized("editProfile.verified.changeRequest.reason")
                        )

                        VerifiedChangeRequestButton(
                            title: AppLanguageManager.localized("editProfile.education.requestUpdate"),
                            systemImage: "graduationcap.fill"
                        ) {
                            changeRequestKind = .education
                        }

                        InlineCompletionHint(
                            isComplete: !schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            completeText: AppLanguageManager.localized("editProfile.education.hint.complete"),
                            incompleteText: AppLanguageManager.localized("editProfile.education.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.prompts.title"),
                        subtitle: AppLanguageManager.localized("editProfile.prompts.subtitle")
                    ) {
                        ProfilePromptEditorView(
                            prompts: $prompts,
                            userId: session.currentUserId
                        )

                        InlineCompletionHint(
                            isComplete: completedPromptCount > 0,
                            completeText: completedPromptCount >= 3 ? AppLanguageManager.localized("editProfile.prompts.hint.allCompleted") : String(format: AppLanguageManager.localized("editProfile.prompts.hint.countCompletedFormat"), completedPromptCount),
                            incompleteText: AppLanguageManager.localized("editProfile.prompts.hint.incomplete")
                        )
                    }

                    EditProfileCardSection(
                        title: AppLanguageManager.localized("editProfile.interests.title"),
                        subtitle: AppLanguageManager.localized("editProfile.interests.subtitle")
                    ) {
                        InterestTagPickerView(
                            selectedInterests: $interests,
                            message: $interestMessage
                        )

                        InlineCompletionHint(
                            isComplete: interests.count >= 3,
                            completeText: interests.count >= 5 ? AppLanguageManager.localized("editProfile.interests.hint.complete") : AppLanguageManager.localized("editProfile.interests.hint.goodSelection"),
                            incompleteText: AppLanguageManager.localized("editProfile.interests.hint.incomplete")
                        )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .textFieldStyle(.roundedBorder)
            .tint(.pink)
            .navigationTitle(AppLanguageManager.localized("editProfile.navigationTitle"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common.close")) {
                        populateFields()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? AppLanguageManager.localized("common.saving") : AppLanguageManager.localized("common.save")) {
                        Task {
                            await saveProfile()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .task {
                populateFields()
                await loadDisplayNameChangeStatus()
                await loadPhotos()
                await loadPrompts()
                await loadInterests()
            }
            .sheet(isPresented: $showingHometownSelector) {
                MalaysiaCitySearchView(title: AppLanguageManager.localized("editProfile.location.searchHometown"), selectedCity: $hometown)
            }
            .sheet(isPresented: $showingCurrentlyLivingSelector) {
                MalaysiaCitySearchView(title: AppLanguageManager.localized("editProfile.location.searchCurrentCity"), selectedCity: $currentlyLiving)
            }
            .sheet(item: $changeRequestKind) { kind in
                ProfileChangeRequestSheet(
                    kind: kind,
                    currentFullName: fullName,
                    currentJobTitle: jobTitle,
                    currentCompanyName: companyName,
                    currentEducationLevel: educationLevel,
                    currentSchoolName: schoolName,
                    educationLevels: ProfileSetupViewModel.educationLevels,
                    isSubmitting: isSubmittingChangeRequest
                ) { request in
                    await submitChangeRequest(request)
                }
            }
            .alert(AppLanguageManager.localized("editProfile.photos.deleteAlert.title"), isPresented: Binding(
                get: { photoPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        photoPendingDeletion = nil
                    }
                }
            )) {
                Button(AppLanguageManager.localized("common.cancel"), role: .cancel) {
                    photoPendingDeletion = nil
                }

                Button(AppLanguageManager.localized("common.delete"), role: .destructive) {
                    guard let photo = photoPendingDeletion else { return }
                    Task {
                        await delete(photo)
                        photoPendingDeletion = nil
                    }
                }
            } message: {
                Text(AppLanguageManager.localized("editProfile.photos.deleteAlert.message"))
            }
        }
    }

    private var displayNameEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(AppLanguageManager.localized("profileSetup.name.displayNamePlaceholder"), text: $displayName)
                .disabled(shouldDisableDisplayNameField)
                .opacity(shouldDisableDisplayNameField ? 0.72 : 1)

            Text(displayNameLimitHint)
                .font(.caption)
                .foregroundStyle(displayNameHintColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayNameHintColor: Color {
        canChangeDisplayNameNow ? .secondary : .orange
    }

    private var validPhotos: [ProfilePhoto] {
        sortedUniquePhotos(photos.filter { photo in
            isUsablePhotoPath(photo.photoPath)
        })
    }

    private func isUsablePhotoPath(_ path: String) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }
        guard trimmedPath != "/" else { return false }
        guard !trimmedPath.localizedCaseInsensitiveContains("placeholder") else { return false }
        guard !trimmedPath.localizedCaseInsensitiveContains("null") else { return false }
        return true
    }

    private var nextAvailablePhotoDisplayOrder: Int {
        let usedOrders = Set(validPhotos.map(\.displayOrder))

        for order in 0..<6 {
            if !usedOrders.contains(order) {
                return order
            }
        }

        return validPhotos.count
    }

    private var completedPromptCount: Int {
        prompts.filter { prompt in
            !prompt.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var lifestyleCompletionCount: Int {
        [
            smoking,
            drinking,
            exercise,
            pets,
            communicationStyle,
            loveLanguage,
            mbti,
            languages,
            familyPlans,
            race,
            religion
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var horoscopeText: String {
        guard let horoscope = Profile(
            id: session.currentUserId ?? UUID(),
            dateOfBirth: formattedDate(dateOfBirth)
        ).horoscope else {
            return AppLanguageManager.localized("editProfile.basics.selectDateOfBirth")
        }

        return LocalizedProfileDisplay.option(horoscope)
    }

    private var isNonWorkingStatus: Bool {
        let title = jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.localizedCaseInsensitiveCompare("Student") == .orderedSame
            || title.localizedCaseInsensitiveCompare("Unemployed") == .orderedSame
    }

    private var localizedJobTitle: String {
        LocalizedProfileDisplay.option(jobTitle)
    }

    private var isDisplayNameEdited: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines) != originalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChangeDisplayNameNow: Bool {
        guard let displayNameChangedAt else { return true }
        let nextAvailableDate = Calendar.current.date(byAdding: .day, value: 30, to: displayNameChangedAt) ?? displayNameChangedAt
        return Date() >= nextAvailableDate
    }

    private var displayNameChangeLockedMessage: String {
        guard let displayNameChangedAt else {
            return AppLanguageManager.localized("editProfile.displayName.changeLimit")
        }

        let nextAvailableDate = Calendar.current.date(byAdding: .day, value: 30, to: displayNameChangedAt) ?? displayNameChangedAt
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return String(
            format: AppLanguageManager.localized("editProfile.displayName.changeLimitWithDate"),
            formatter.string(from: nextAvailableDate)
        )
    }

    private var displayNameLimitHint: String {
        if canChangeDisplayNameNow {
            return AppLanguageManager.localized("editProfile.displayName.changeHint")
        }

        return displayNameChangeLockedMessage
    }

    private var shouldDisableDisplayNameField: Bool {
        !canChangeDisplayNameNow && !isDisplayNameEdited
    }

    private func populateFields() {
        guard let profile = session.currentProfile else { return }

        fullName = profile.fullName ?? ""
        displayName = profile.displayName ?? ""
        originalDisplayName = profile.displayName ?? ""
        dateOfBirth = parseDate(profile.dateOfBirth) ?? defaultDateOfBirth()
        gender = profile.gender ?? .male
        race = profile.race ?? ""
        religion = profile.religion ?? ""
        hometown = profile.hometown ?? ""
        currentlyLiving = profile.currentlyLiving ?? profile.city ?? ""
        bio = profile.bio ?? ""
        jobTitle = profile.jobTitle ?? ""
        companyName = profile.companyName ?? ""
        educationLevel = profile.educationLevel ?? ProfileSetupViewModel.educationLevels.first ?? "Secondary"
        schoolName = profile.schoolName ?? ""
        heightCm = profile.heightCm ?? 170
        relationshipGoal = profile.relationshipGoal ?? .serious_relationship
        genderInterest = profile.genderInterest ?? .opposite_gender
        maritalStatus = profile.maritalStatus ?? .single
        smoking = profile.smoking ?? ""
        drinking = profile.drinking ?? ""
        exercise = profile.exercise ?? ""
        pets = profile.pets ?? ""
        communicationStyle = profile.communicationStyle ?? ""
        loveLanguage = profile.loveLanguage ?? ""
        mbti = profile.mbti ?? ""
        languages = profile.languages ?? ""
        familyPlans = profile.familyPlans ?? ""
    }

    private func saveProfile() async {
        guard let userId = session.currentUserId else { return }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDisplayName.isEmpty else {
            errorMessage = AppLanguageManager.localized("editProfile.error.displayNameRequired")
            return
        }

        let originalTrimmedDisplayName = originalDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isChangingDisplayName = trimmedDisplayName != originalTrimmedDisplayName

        if isChangingDisplayName, !canChangeDisplayNameNow {
            errorMessage = displayNameChangeLockedMessage
            return
        }

        isSaving = true
        errorMessage = nil

        struct UpdatePayload: Encodable {
            let display_name: String
            let display_name_changed_at: String?
            let date_of_birth: String
            let gender: String
            let marital_status: String
            let race: String?
            let religion: String?
            let hometown: String?
            let currently_living: String?
            let city: String?
            let bio: String
            let height_cm: Int
            let relationship_goal: String
            let gender_interest: String
            let smoking: String?
            let drinking: String?
            let exercise: String?
            let pets: String?
            let communication_style: String?
            let love_language: String?
            let mbti: String?
            let languages: String?
            let family_plans: String?
        }

        do {
            try await supabase
                .from("profiles")
                .update(
                    UpdatePayload(
                        display_name: trimmedDisplayName,
                        display_name_changed_at: isChangingDisplayName ? iso8601String(from: Date()) : displayNameChangedAtStorageValue,
                        date_of_birth: formattedDate(dateOfBirth),
                        gender: gender.rawValue,
                        marital_status: maritalStatus.rawValue,
                        race: cleanedOptional(race),
                        religion: cleanedOptional(religion),
                        hometown: hometown.isEmpty ? nil : hometown,
                        currently_living: currentlyLiving.isEmpty ? nil : currentlyLiving,
                        city: currentlyLiving.isEmpty ? nil : currentlyLiving,
                        bio: bio,
                        height_cm: heightCm,
                        relationship_goal: relationshipGoal.rawValue,
                        gender_interest: genderInterest.rawValue,
                        smoking: cleanedOptional(smoking),
                        drinking: cleanedOptional(drinking),
                        exercise: cleanedOptional(exercise),
                        pets: cleanedOptional(pets),
                        communication_style: cleanedOptional(communicationStyle),
                        love_language: cleanedOptional(loveLanguage),
                        mbti: cleanedOptional(mbti),
                        languages: cleanedOptional(languages),
                        family_plans: cleanedOptional(familyPlans)
                    )
                )
                .eq("id", value: userId)
                .execute()

            try await ProfilePromptService.shared.saveProfilePrompts(userId: userId, prompts: prompts)
            try await ProfileInterestService.shared.saveProfileInterests(userId: userId, interests: interests)
            await session.loadProfile()
            originalDisplayName = trimmedDisplayName
            if isChangingDisplayName {
                displayNameChangedAt = Date()
                displayNameChangedAtStorageValue = iso8601String(from: displayNameChangedAt)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func submitChangeRequest(_ request: ProfileChangeRequestDraft) async -> Bool {
        guard let userId = session.currentUserId else { return false }

        struct ChangeRequestPayload: Encodable {
            let user_id: UUID
            let request_type: String
            let current_full_name: String?
            let requested_full_name: String?
            let current_job_title: String?
            let requested_job_title: String?
            let current_company_name: String?
            let requested_company_name: String?
            let current_education_level: String?
            let requested_education_level: String?
            let current_school_name: String?
            let requested_school_name: String?
            let message: String?
            let attachment_file_path: String?
            let attachment_file_name: String?
            let attachment_content_type: String?
            let attachment_source: String?
        }

        isSubmittingChangeRequest = true
        errorMessage = nil
        defer { isSubmittingChangeRequest = false }

        do {
            let attachmentPath = try await uploadChangeRequestAttachment(
                request.attachment,
                userId: userId,
                requestType: request.kind.rawValue
            )

            try await supabase
                .from("profile_change_requests")
                .insert(
                    ChangeRequestPayload(
                        user_id: userId,
                        request_type: request.kind.rawValue,
                        current_full_name: cleanedOptional(request.currentFullName),
                        requested_full_name: cleanedOptional(request.requestedFullName),
                        current_job_title: cleanedOptional(request.currentJobTitle),
                        requested_job_title: cleanedOptional(request.requestedJobTitle),
                        current_company_name: cleanedOptional(request.currentCompanyName),
                        requested_company_name: cleanedOptional(request.requestedCompanyName),
                        current_education_level: cleanedOptional(request.currentEducationLevel),
                        requested_education_level: cleanedOptional(request.requestedEducationLevel),
                        current_school_name: cleanedOptional(request.currentSchoolName),
                        requested_school_name: cleanedOptional(request.requestedSchoolName),
                        message: cleanedOptional(request.message),
                        attachment_file_path: attachmentPath,
                        attachment_file_name: request.attachment?.fileName,
                        attachment_content_type: request.attachment?.contentType,
                        attachment_source: request.attachment?.source.rawValue
                    )
                )
                .execute()

            errorMessage = AppLanguageManager.localized("editProfile.changeRequest.submitted")
            return true
        } catch {
            errorMessage = String.localizedStringWithFormat(
                AppLanguageManager.localized("editProfile.changeRequest.submitFailedFormat"),
                error.localizedDescription
            )
            return false
        }
    }

    private func uploadChangeRequestAttachment(
        _ attachment: ProfileChangeRequestAttachment?,
        userId: UUID,
        requestType: String
    ) async throws -> String? {
        guard let attachment else { return nil }

        let data: Data
        if let fileURL = attachment.fileURL {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            data = try Data(contentsOf: fileURL)
        } else if let attachmentData = attachment.data {
            data = attachmentData
        } else {
            return nil
        }

        let fileName = cleanFileName(attachment.fileName, fallback: "profile-change-proof.jpg")
        let path = "\(userId.uuidString)/profile-change-requests/\(requestType)/\(UUID().uuidString)-\(fileName)"

        try await supabase.storage
            .from("verification-documents")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: attachment.contentType, upsert: false)
            )

        return path
    }

    private func cleanFileName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = value
            .components(separatedBy: allowed.inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))

        return cleaned.isEmpty ? fallback : cleaned
    }

    private func savePhotoOrder(_ orderedPhotos: [ProfilePhoto]) async {
        guard let userId = session.currentUserId else { return }
        guard !orderedPhotos.isEmpty else { return }

        photoMutationRevision += 1
        let revision = photoMutationRevision
        photoReorderInProgress = true
        errorMessage = nil
        photos = photosWithUpdatedDisplayOrder(orderedPhotos)

        struct ProfilePrimaryPhotoPayload: Encodable {
            let profile_photo_url: String?
        }

        do {
            let savedPhotos = try await ProfilePhotoService.shared.savePhotoOrder(
                userId: userId,
                orderedPhotos: orderedPhotos
            )

            guard revision == photoMutationRevision else { return }

            photos = sortedUniquePhotos(savedPhotos)

            try await supabase
                .from("profiles")
                .update(ProfilePrimaryPhotoPayload(profile_photo_url: orderedPhotos.first?.photoPath))
                .eq("id", value: userId)
                .execute()

            guard revision == photoMutationRevision else { return }

            photoReorderInProgress = false
            await session.loadProfile()
        } catch {
            guard revision == photoMutationRevision else { return }

            errorMessage = error.localizedDescription
            photoReorderInProgress = false
        }
    }

    private func handleUploadedPhoto(_ uploadedPhoto: ProfilePhoto) async {
        photoMutationRevision += 1
        photoReorderInProgress = false
        errorMessage = nil

        var mergedPhotos = validPhotos.filter { photo in
            photo.id != uploadedPhoto.id
        }
        mergedPhotos.append(uploadedPhoto)
        photos = compactedPhotosForSlots(mergedPhotos)

        if uploadedPhoto.displayOrder == 0 {
            await session.loadProfile()
        }
    }

    private func photosWithUpdatedDisplayOrder(_ orderedPhotos: [ProfilePhoto]) -> [ProfilePhoto] {
        orderedPhotos.enumerated().map { index, photo in
            ProfilePhoto(
                id: photo.id,
                userId: photo.userId,
                photoPath: photo.photoPath,
                displayOrder: index,
                createdAt: photo.createdAt
            )
        }
    }

    private func setPrimaryPhoto(_ selectedPhoto: ProfilePhoto) async {
        guard let userId = session.currentUserId else { return }
        guard selectedPhoto.displayOrder != 0 else { return }

        primaryPhotoUpdateInProgressId = selectedPhoto.id
        errorMessage = nil

        struct PhotoOrderUpdatePayload: Encodable {
            let display_order: Int
        }

        struct ProfilePrimaryPhotoPayload: Encodable {
            let profile_photo_url: String?
        }

        do {
            let selectedOriginalOrder = selectedPhoto.displayOrder
            let sortedPhotos = validPhotos.sorted { $0.displayOrder < $1.displayOrder }

            if let currentPrimaryPhoto = sortedPhotos.first(where: { $0.displayOrder == 0 }) {
                try await supabase
                    .from("profile_photos")
                    .update(PhotoOrderUpdatePayload(display_order: -1))
                    .eq("id", value: selectedPhoto.id)
                    .eq("user_id", value: userId)
                    .execute()

                try await supabase
                    .from("profile_photos")
                    .update(PhotoOrderUpdatePayload(display_order: selectedOriginalOrder))
                    .eq("id", value: currentPrimaryPhoto.id)
                    .eq("user_id", value: userId)
                    .execute()
            }

            try await supabase
                .from("profile_photos")
                .update(PhotoOrderUpdatePayload(display_order: 0))
                .eq("id", value: selectedPhoto.id)
                .eq("user_id", value: userId)
                .execute()

            try await supabase
                .from("profiles")
                .update(ProfilePrimaryPhotoPayload(profile_photo_url: selectedPhoto.photoPath))
                .eq("id", value: userId)
                .execute()

            await loadPhotos()
            await session.loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }

        primaryPhotoUpdateInProgressId = nil
    }

    private func loadDisplayNameChangeStatus() async {
        guard let userId = session.currentUserId else { return }

        struct DisplayNameChangeStatus: Decodable {
            let display_name_changed_at: String?
        }

        do {
            let response: DisplayNameChangeStatus = try await supabase
                .from("profiles")
                .select("display_name_changed_at")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            displayNameChangedAtStorageValue = response.display_name_changed_at
            displayNameChangedAt = parseISO8601Date(response.display_name_changed_at)
        } catch {
            print("Failed to load display name change status:", error.localizedDescription)
        }
    }

    private func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func iso8601String(from date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    private func loadPhotos() async {
        await loadPhotos(revision: nil)
    }

    private func loadPhotos(revision: Int?) async {
        guard let userId = session.currentUserId else { return }

        do {
            let fetchedPhotos = try await ProfilePhotoService.shared.fetchPhotos(userId: userId)
            let fetchedUsablePhotos = await usablePhotos(from: fetchedPhotos)
            let compactedPhotos = compactedPhotosForSlots(fetchedUsablePhotos)

            guard revision == nil || revision == photoMutationRevision else { return }

            photos = compactedPhotos
            await ensurePrimaryPhotoIfNeeded(userId: userId, revision: revision)

            if needsPhotoOrderCompaction(originalPhotos: fetchedUsablePhotos, compactedPhotos: compactedPhotos) {
                let savedPhotos = try await ProfilePhotoService.shared.savePhotoOrder(
                    userId: userId,
                    orderedPhotos: compactedPhotos
                )

                guard revision == nil || revision == photoMutationRevision else { return }

                photos = compactedPhotosForSlots(savedPhotos)
            }
        } catch {
            guard revision == nil || revision == photoMutationRevision else { return }

            errorMessage = error.localizedDescription
        }
    }

    private func usablePhotos(from fetchedPhotos: [ProfilePhoto]) async -> [ProfilePhoto] {
        fetchedPhotos.filter { isUsablePhotoPath($0.photoPath) }
    }

    private func ensurePrimaryPhotoIfNeeded(userId: UUID, revision: Int? = nil) async {
        guard !validPhotos.isEmpty else { return }
        guard !validPhotos.contains(where: { $0.displayOrder == 0 }) else { return }
        guard let firstPhoto = validPhotos.sorted(by: { lhs, rhs in
            if lhs.displayOrder == rhs.displayOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.displayOrder < rhs.displayOrder
        }).first else { return }

        struct PhotoOrderUpdatePayload: Encodable {
            let display_order: Int
        }

        struct ProfilePrimaryPhotoPayload: Encodable {
            let profile_photo_url: String?
        }

        do {
            try await supabase
                .from("profile_photos")
                .update(PhotoOrderUpdatePayload(display_order: 0))
                .eq("id", value: firstPhoto.id)
                .eq("user_id", value: userId)
                .execute()

            try await supabase
                .from("profiles")
                .update(ProfilePrimaryPhotoPayload(profile_photo_url: firstPhoto.photoPath))
                .eq("id", value: userId)
                .execute()

            let fetchedPhotos = try await ProfilePhotoService.shared.fetchPhotos(userId: userId)
            let fetchedUsablePhotos = await usablePhotos(from: fetchedPhotos)
            let compactedPhotos = compactedPhotosForSlots(fetchedUsablePhotos)

            guard revision == nil || revision == photoMutationRevision else { return }

            photos = compactedPhotos
            await session.loadProfile()
        } catch {
            guard revision == nil || revision == photoMutationRevision else { return }

            errorMessage = error.localizedDescription
        }
    }

    private func loadPrompts() async {
        guard let userId = session.currentUserId else { return }

        do {
            prompts = try await ProfilePromptService.shared.loadProfilePrompts(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadInterests() async {
        guard let userId = session.currentUserId else { return }

        do {
            interests = try await ProfileInterestService.shared.loadProfileInterests(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ photo: ProfilePhoto) async {
        photoMutationRevision += 1
        let revision = photoMutationRevision
        photoReorderInProgress = false
        errorMessage = nil

        do {
            try await ProfilePhotoService.shared.deletePhoto(photo: photo)
            guard revision == photoMutationRevision else { return }

            photos = compactedPhotosForSlots(photos.filter { $0.id != photo.id })
            await loadPhotos(revision: revision)
        } catch {
            guard revision == photoMutationRevision else { return }

            errorMessage = error.localizedDescription
        }
    }

    private func sortedUniquePhotos(_ sourcePhotos: [ProfilePhoto]) -> [ProfilePhoto] {
        var seenPhotoIds = Set<UUID>()

        return sourcePhotos
            .filter { photo in
                guard !seenPhotoIds.contains(photo.id) else { return false }
                seenPhotoIds.insert(photo.id)
                return true
            }
            .sorted { lhs, rhs in
                if lhs.displayOrder == rhs.displayOrder {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.displayOrder < rhs.displayOrder
            }
    }

    private func compactedPhotosForSlots(_ sourcePhotos: [ProfilePhoto]) -> [ProfilePhoto] {
        sortedUniquePhotos(sourcePhotos).enumerated().map { index, photo in
            ProfilePhoto(
                id: photo.id,
                userId: photo.userId,
                photoPath: photo.photoPath,
                displayOrder: index,
                createdAt: photo.createdAt
            )
        }
    }

    private func needsPhotoOrderCompaction(
        originalPhotos: [ProfilePhoto],
        compactedPhotos: [ProfilePhoto]
    ) -> Bool {
        let originalById = Dictionary(uniqueKeysWithValues: sortedUniquePhotos(originalPhotos).map { ($0.id, $0.displayOrder) })

        return compactedPhotos.contains { photo in
            originalById[photo.id] != photo.displayOrder
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func cleanedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func defaultDateOfBirth() -> Date {
        Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    }
}
private extension GenderInterest {
    var title: String {
        switch self {
        case .opposite_gender:
            return AppLanguageManager.localized("genderInterest.oppositeGender")
        case .men:
            return AppLanguageManager.localized("genderInterest.men")
        case .women:
            return AppLanguageManager.localized("genderInterest.women")
        case .everyone:
            return AppLanguageManager.localized("genderInterest.everyone")
        }
    }
}

private extension MaritalStatus {
    var title: String {
        switch self {
        case .single:
            return AppLanguageManager.localized("maritalStatus.single")
        case .divorced:
            return AppLanguageManager.localized("maritalStatus.divorced")
        case .widowed:
            return AppLanguageManager.localized("maritalStatus.widowed")
        case .separated:
            return AppLanguageManager.localized("maritalStatus.separated")
        case .prefer_not_to_say:
            return AppLanguageManager.localized("maritalStatus.preferNotToSay")
        }
    }
}

private struct ProfilePhotoSlotsView: View {
    let photos: [ProfilePhoto]
    let userId: UUID?
    let primaryPhotoUpdateInProgressId: UUID?
    let photoReorderInProgress: Bool
    let onUploadCompleted: (ProfilePhoto) async -> Void
    let onSaveOrder: ([ProfilePhoto]) -> Void
    let onDelete: (ProfilePhoto) -> Void

    private let maxPhotos = 6
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    @State private var localOrderedPhotos: [ProfilePhoto] = []
    @State private var draggingPhoto: ProfilePhoto?
    @State private var dragStartPhotos: [ProfilePhoto] = []
    @State private var previewedDropTargetId: UUID?

    private var sortedInputPhotos: [ProfilePhoto] {
        photos.sorted { lhs, rhs in
            if lhs.displayOrder == rhs.displayOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.displayOrder < rhs.displayOrder
        }
    }

    private var visiblePhotos: [ProfilePhoto] {
        guard draggingPhoto != nil || photoReorderInProgress else {
            return sortedInputPhotos
        }

        return localOrderedPhotos.isEmpty ? sortedInputPhotos : localOrderedPhotos
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<maxPhotos, id: \.self) { index in
                if index < visiblePhotos.count {
                    let photo = visiblePhotos[index]

                    ProfilePhotoSlotCard(
                        photo: photo,
                        slotNumber: index + 1,
                        isPrimary: index == 0,
                        isUpdatingPrimary: primaryPhotoUpdateInProgressId == photo.id,
                        isReorderDisabled: photoReorderInProgress,
                        isDragging: draggingPhoto?.id == photo.id,
                        onDelete: {
                            onDelete(photo)
                        },
                        onDragStarted: {
                            beginDragging(photo)
                        }
                    )
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: ProfilePhotoDropDelegate(
                            targetPhoto: photo,
                            photos: $localOrderedPhotos,
                            draggingPhoto: $draggingPhoto,
                            dragStartPhotos: $dragStartPhotos,
                            previewedDropTargetId: $previewedDropTargetId,
                            onSaveOrder: onSaveOrder
                        )
                    )
                } else {
                    EmptyProfilePhotoSlot(
                        slotNumber: index + 1,
                        userId: userId,
                        displayOrder: index,
                        maxSelectionCount: maxPhotos - index,
                        onUploadCompleted: onUploadCompleted
                    )
                }
            }
        }
        .onAppear {
            localOrderedPhotos = sortedInputPhotos
        }
        .onChange(of: photos) { _, newPhotos in
            guard draggingPhoto == nil else { return }
            localOrderedPhotos = newPhotos.sorted { lhs, rhs in
                if lhs.displayOrder == rhs.displayOrder {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.displayOrder < rhs.displayOrder
            }
        }
        .onChange(of: photoReorderInProgress) { _, isReordering in
            guard !isReordering else { return }
            localOrderedPhotos = sortedInputPhotos
            dragStartPhotos = []
            previewedDropTargetId = nil
        }
    }

    private func beginDragging(_ photo: ProfilePhoto) {
        guard !photoReorderInProgress else { return }
        if localOrderedPhotos.isEmpty {
            localOrderedPhotos = sortedInputPhotos
        }
        HapticManager.light()
        draggingPhoto = photo
        dragStartPhotos = localOrderedPhotos
        previewedDropTargetId = nil
    }
}

private struct ProfilePhotoSlotCard: View {
    let photo: ProfilePhoto
    let slotNumber: Int
    let isPrimary: Bool
    let isUpdatingPrimary: Bool
    let isReorderDisabled: Bool
    let isDragging: Bool
    let onDelete: () -> Void
    let onDragStarted: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            slotTitle

            fixedPhotoCard
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isDragging ? 0.96 : 1)
            .opacity(isDragging ? 0.72 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isDragging)
            .onDrag {
                guard !isReorderDisabled else { return NSItemProvider() }
                onDragStarted()
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.plainText.identifier,
                    visibility: .all
                ) { completion in
                    completion(Data(photo.id.uuidString.utf8), nil)
                    return nil
                }
                provider.suggestedName = photo.id.uuidString
                return provider
            } preview: {
                ProfilePhotoDragPreview(
                    photoPath: photo.photoPath
                )
            }
            .task(id: photo.photoPath) {
                await loadImage(for: photo.photoPath)
            }
    }

    private var slotTitle: some View {
        Text(isPrimary ? AppLanguageManager.localized("editProfile.photos.primaryPhoto") : String(format: AppLanguageManager.localized("editProfile.photos.photoNumberFormat"), slotNumber))
            .font(.caption.weight(.bold))
            .foregroundStyle(isPrimary ? .pink : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fixedPhotoCard: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                photoContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if isPrimary {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.pink, lineWidth: 2)
                        }
                    }

                topControls
            }
        }
        .aspectRatio(0.76, contentMode: .fit)
    }

    private var photoContent: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                thumbnailPlaceholder
                    .overlay {
                        if isLoading {
                            ProgressView()
                        }
                    }
            }
        }
    }

    private var topControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if isPrimary {
                    Label(AppLanguageManager.localized("editProfile.photos.primary"), systemImage: "sparkles")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.pink, in: Circle())
                        .accessibilityLabel(AppLanguageManager.localized("editProfile.photos.primary"))
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingPrimary || isReorderDisabled)
                .accessibilityLabel(AppLanguageManager.localized("editProfile.photos.deletePhoto"))
            }

            Spacer()
        }
        .padding(8)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func loadImage(for path: String) async {
        if let cachedImage = ProfilePhotoService.shared.cachedImage(for: path) {
            image = cachedImage
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let loadedImage = try await ProfilePhotoService.shared.image(for: path)
            guard path == photo.photoPath else { return }
            image = loadedImage
        } catch {
            print("Failed to load profile photo thumbnail:", error.localizedDescription)
        }
    }
}

private struct ProfilePhotoDropDelegate: DropDelegate {
    let targetPhoto: ProfilePhoto
    @Binding var photos: [ProfilePhoto]
    @Binding var draggingPhoto: ProfilePhoto?
    @Binding var dragStartPhotos: [ProfilePhoto]
    @Binding var previewedDropTargetId: UUID?
    let onSaveOrder: ([ProfilePhoto]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard previewedDropTargetId != targetPhoto.id else { return }
        if previewSwapForTarget() {
            previewedDropTargetId = targetPhoto.id
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingPhoto != nil else {
            DispatchQueue.main.async {
                draggingPhoto = nil
            }
            return false
        }

        if previewedDropTargetId != targetPhoto.id {
            _ = previewSwapForTarget()
        }

        let orderedPhotos = photos

        DispatchQueue.main.async {
            draggingPhoto = nil
            dragStartPhotos = []
            previewedDropTargetId = nil
            onSaveOrder(orderedPhotos)
        }

        return true
    }

    private func previewSwapForTarget() -> Bool {
        guard let sourcePhoto = draggingPhoto,
              sourcePhoto.id != targetPhoto.id,
              let fromIndex = dragStartPhotos.firstIndex(where: { $0.id == sourcePhoto.id }),
              let toIndex = dragStartPhotos.firstIndex(where: { $0.id == targetPhoto.id }),
              fromIndex != toIndex
        else { return false }

        var swappedPhotos = dragStartPhotos
        swappedPhotos.swapAt(fromIndex, toIndex)

        HapticManager.light()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            photos = swappedPhotos
        }

        return true
    }
}

private struct ProfilePhotoDragPreview: View {
    let photoPath: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: 118, height: 154)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .task(id: photoPath) {
            image = try? await ProfilePhotoService.shared.image(for: photoPath)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyProfilePhotoSlot: View {
    let slotNumber: Int
    let userId: UUID?
    let displayOrder: Int
    let maxSelectionCount: Int
    let onUploadCompleted: (ProfilePhoto) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            slotTitle

            if let userId {
            PhotoUploadPicker(
                userId: userId,
                displayOrder: displayOrder,
                slotNumber: slotNumber,
                maxSelectionCount: maxSelectionCount,
                onUploaded: onUploadCompleted
            )
                .buttonStyle(.plain)
            } else {
                emptySlotContent
            }
        }
        .accessibilityLabel(String(format: AppLanguageManager.localized("editProfile.photos.addPhotoToSlotFormat"), slotNumber))
    }

    private var slotTitle: some View {
        Text(slotNumber == 1 ? AppLanguageManager.localized("editProfile.photos.primaryPhoto") : String(format: AppLanguageManager.localized("editProfile.photos.photoNumberFormat"), slotNumber))
            .font(.caption.weight(.bold))
            .foregroundStyle(slotNumber == 1 ? .pink : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptySlotContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.pink)

            Text(slotNumber == 1 ? AppLanguageManager.localized("editProfile.photos.addPrimary") : AppLanguageManager.localized("editProfile.photos.addPhoto"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text(String(format: AppLanguageManager.localized("editProfile.photos.slotNumberFormat"), slotNumber))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.76, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(Color.pink.opacity(0.35))
        }
    }
}

private struct PhotoCompletionHint: View {
    let photoCount: Int

    private var title: String {
        switch photoCount {
        case 0:
            return AppLanguageManager.localized("editProfile.photos.hint.firstPhotoTitle")
        case 1...2:
            return AppLanguageManager.localized("editProfile.photos.hint.addAtLeastThreeTitle")
        case 3...5:
            return AppLanguageManager.localized("editProfile.photos.hint.strongSetTitle")
        default:
            return AppLanguageManager.localized("editProfile.photos.hint.completeTitle")
        }
    }

    private var message: String {
        switch photoCount {
        case 0:
            return AppLanguageManager.localized("editProfile.photos.hint.firstPhotoMessage")
        case 1...2:
            return AppLanguageManager.localized("editProfile.photos.hint.addAtLeastThreeMessage")
        case 3...5:
            return AppLanguageManager.localized("editProfile.photos.hint.strongSetMessage")
        default:
            return AppLanguageManager.localized("editProfile.photos.hint.completeMessage")
        }
    }

    private var iconName: String {
        photoCount >= 3 ? "checkmark.seal.fill" : "camera.fill"
    }

    private var iconColor: Color {
        photoCount >= 3 ? .green : .pink
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(iconColor.opacity(0.12), in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.pink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.pink.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct EmptyProfilePhotosView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.pink)
                .frame(width: 26, height: 26)
                .background(Color.pink.opacity(0.12), in: Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLanguageManager.localized("editProfile.photos.empty.title"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppLanguageManager.localized("editProfile.photos.empty.message"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.pink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.pink.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct LockedVerifiedFieldRow: View {
    let title: String
    let value: String
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Label(AppLanguageManager.localized("common.verified"), systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1), in: Capsule())
            }

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
    }
}

private struct VerifiedChangeRequestButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.pink)
        .controlSize(.regular)
    }
}

private enum ProfileChangeRequestKind: String, Identifiable, CaseIterable {
    case legalName = "legal_name"
    case work = "work"
    case education = "education"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legalName:
            return AppLanguageManager.localized("editProfile.changeRequest.legalName.title")
        case .work:
            return AppLanguageManager.localized("editProfile.changeRequest.work.title")
        case .education:
            return AppLanguageManager.localized("editProfile.changeRequest.education.title")
        }
    }

    var message: String {
        switch self {
        case .legalName:
            return AppLanguageManager.localized("editProfile.changeRequest.legalName.message")
        case .work:
            return AppLanguageManager.localized("editProfile.changeRequest.work.message")
        case .education:
            return AppLanguageManager.localized("editProfile.changeRequest.education.message")
        }
    }
}

private struct ProfileChangeRequestDraft {
    let kind: ProfileChangeRequestKind
    let currentFullName: String
    let requestedFullName: String
    let currentJobTitle: String
    let requestedJobTitle: String
    let currentCompanyName: String
    let requestedCompanyName: String
    let currentEducationLevel: String
    let requestedEducationLevel: String
    let currentSchoolName: String
    let requestedSchoolName: String
    let message: String
    let attachment: ProfileChangeRequestAttachment?
}

private enum ProfileChangeRequestAttachmentSource: String {
    case photos
    case camera
    case files
}

private struct ProfileChangeRequestAttachment {
    let fileName: String
    let contentType: String
    let data: Data?
    let fileURL: URL?
    let source: ProfileChangeRequestAttachmentSource

    var displayName: String { fileName }

    static func photo(data: Data, fileName: String, contentType: String, source: ProfileChangeRequestAttachmentSource) -> ProfileChangeRequestAttachment {
        ProfileChangeRequestAttachment(fileName: fileName, contentType: contentType, data: data, fileURL: nil, source: source)
    }

    static func file(url: URL, contentType: String) -> ProfileChangeRequestAttachment {
        ProfileChangeRequestAttachment(fileName: url.lastPathComponent, contentType: contentType, data: nil, fileURL: url, source: .files)
    }
}

private struct ProfileChangeRequestSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kind: ProfileChangeRequestKind
    let currentFullName: String
    let currentJobTitle: String
    let currentCompanyName: String
    let currentEducationLevel: String
    let currentSchoolName: String
    let educationLevels: [String]
    let isSubmitting: Bool
    let onSubmit: (ProfileChangeRequestDraft) async -> Bool

    @State private var requestedFullName: String
    @State private var requestedJobTitle: String
    @State private var requestedCompanyName: String
    @State private var requestedEducationLevel: String
    @State private var requestedSchoolName: String
    @State private var message = ""
    @State private var attachment: ProfileChangeRequestAttachment?
    @State private var localError: String?

    init(
        kind: ProfileChangeRequestKind,
        currentFullName: String,
        currentJobTitle: String,
        currentCompanyName: String,
        currentEducationLevel: String,
        currentSchoolName: String,
        educationLevels: [String],
        isSubmitting: Bool,
        onSubmit: @escaping (ProfileChangeRequestDraft) async -> Bool
    ) {
        self.kind = kind
        self.currentFullName = currentFullName
        self.currentJobTitle = currentJobTitle
        self.currentCompanyName = currentCompanyName
        self.currentEducationLevel = currentEducationLevel
        self.currentSchoolName = currentSchoolName
        self.educationLevels = educationLevels
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        _requestedFullName = State(initialValue: currentFullName)
        _requestedJobTitle = State(initialValue: currentJobTitle)
        _requestedCompanyName = State(initialValue: currentCompanyName)
        _requestedEducationLevel = State(initialValue: currentEducationLevel.isEmpty ? (educationLevels.first ?? "") : currentEducationLevel)
        _requestedSchoolName = State(initialValue: currentSchoolName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(kind.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch kind {
                case .legalName:
                    Section(AppLanguageManager.localized("editProfile.changeRequest.currentName")) {
                        ChangeRequestCurrentValueRow(
                            title: AppLanguageManager.localized("profileSetup.name.fullNamePlaceholder"),
                            value: currentFullName
                        )
                    }
                    Section(AppLanguageManager.localized("editProfile.changeRequest.updateName")) {
                        TextField(AppLanguageManager.localized("profileSetup.name.fullNamePlaceholder"), text: $requestedFullName)
                            .textInputAutocapitalization(.words)
                    }
                case .work:
                    Section(AppLanguageManager.localized("editProfile.changeRequest.currentJobDetails")) {
                        ChangeRequestCurrentValueRow(title: AppLanguageManager.localized("editProfile.work.jobTitle"), value: currentJobTitle)
                        ChangeRequestCurrentValueRow(title: AppLanguageManager.localized("editProfile.work.company"), value: currentCompanyName)
                    }
                    Section(AppLanguageManager.localized("editProfile.changeRequest.updateJobDetails")) {
                        TextField(AppLanguageManager.localized("editProfile.work.jobTitle"), text: $requestedJobTitle)
                            .textInputAutocapitalization(.words)
                        TextField(AppLanguageManager.localized("editProfile.work.company"), text: $requestedCompanyName)
                            .textInputAutocapitalization(.words)
                    }
                case .education:
                    Section(AppLanguageManager.localized("editProfile.changeRequest.currentEducationDetails")) {
                        ChangeRequestCurrentValueRow(title: AppLanguageManager.localized("editProfile.education.level"), value: currentEducationLevel.isEmpty ? "" : LocalizedProfileDisplay.option(currentEducationLevel))
                        ChangeRequestCurrentValueRow(title: AppLanguageManager.localized("editProfile.education.school"), value: currentSchoolName)
                    }
                    Section(AppLanguageManager.localized("editProfile.changeRequest.updateEducationDetails")) {
                        Picker(AppLanguageManager.localized("editProfile.education.level"), selection: $requestedEducationLevel) {
                            ForEach(educationLevels, id: \.self) { level in
                                Text(LocalizedProfileDisplay.option(level)).tag(level)
                            }
                        }
                        TextField(AppLanguageManager.localized("editProfile.education.school"), text: $requestedSchoolName)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section(AppLanguageManager.localized("editProfile.changeRequest.attachment")) {
                    ProfileChangeRequestAttachmentPicker(
                        attachment: $attachment,
                        sourceMode: kind == .legalName ? .cameraOnly : .allSources
                    )
                }

                Section(AppLanguageManager.localized("editProfile.changeRequest.note")) {
                    TextField(AppLanguageManager.localized("editProfile.changeRequest.notePlaceholder"), text: $message, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let localError {
                    Text(localError)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSubmitting ? AppLanguageManager.localized("common.saving") : AppLanguageManager.localized("editProfile.changeRequest.submit")) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        guard hasRequestedChange else {
            localError = AppLanguageManager.localized("editProfile.changeRequest.noChange")
            return
        }

        localError = nil
        let didSubmit = await onSubmit(
            ProfileChangeRequestDraft(
                kind: kind,
                currentFullName: currentFullName,
                requestedFullName: requestedFullName,
                currentJobTitle: currentJobTitle,
                requestedJobTitle: requestedJobTitle,
                currentCompanyName: currentCompanyName,
                requestedCompanyName: requestedCompanyName,
                currentEducationLevel: currentEducationLevel,
                requestedEducationLevel: requestedEducationLevel,
                currentSchoolName: currentSchoolName,
                requestedSchoolName: requestedSchoolName,
                message: message,
                attachment: attachment
            )
        )

        if didSubmit {
            dismiss()
        }
    }

    private var hasRequestedChange: Bool {
        switch kind {
        case .legalName:
            return clean(requestedFullName) != clean(currentFullName)
        case .work:
            return clean(requestedJobTitle) != clean(currentJobTitle)
                || clean(requestedCompanyName) != clean(currentCompanyName)
        case .education:
            return clean(requestedEducationLevel) != clean(currentEducationLevel)
                || clean(requestedSchoolName) != clean(currentSchoolName)
        }
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChangeRequestCurrentValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppLanguageManager.localized("editProfile.common.notProvided") : value)
                .font(.body)
                .foregroundStyle(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

private enum ProfileChangeRequestAttachmentSourceMode {
    case cameraOnly
    case allSources
}

private struct ProfileChangeRequestAttachmentPicker: View {
    @Binding var attachment: ProfileChangeRequestAttachment?
    let sourceMode: ProfileChangeRequestAttachmentSourceMode

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isChoosingSource = false
    @State private var isPickingPhoto = false
    @State private var isUsingCamera = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if sourceMode == .cameraOnly {
                    openCamera()
                } else {
                    isChoosingSource = true
                }
            } label: {
                Label(
                    attachment?.displayName ?? AppLanguageManager.localized("editProfile.changeRequest.attachment.add"),
                    systemImage: attachment == nil ? "paperclip" : "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if attachment != nil {
                Button(role: .destructive) {
                    attachment = nil
                } label: {
                    Label(AppLanguageManager.localized("editProfile.changeRequest.attachment.remove"), systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(AppLanguageManager.localized("editProfile.changeRequest.attachment.chooseSource"), isPresented: $isChoosingSource, titleVisibility: .visible) {
            Button(AppLanguageManager.localized("verificationUpload.document.source.photos")) {
                isPickingPhoto = true
            }
            Button(AppLanguageManager.localized("verificationUpload.document.source.camera")) {
                openCamera()
            }
            Button(AppLanguageManager.localized("verificationUpload.document.source.files")) {
                isImporting = true
            }
            Button(AppLanguageManager.localized("common_cancel"), role: .cancel) {}
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    errorMessage = AppLanguageManager.localized("verificationUpload.error.noFileSelected")
                    return
                }
                attachment = .file(url: url, contentType: contentType(for: url))
                errorMessage = nil
            case .failure(let error):
                errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.importFileFormat"), error.localizedDescription)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
        .sheet(isPresented: $isUsingCamera) {
            ProfileChangeRequestPhotoCamera { image in
                loadCameraImage(image)
            }
            .ignoresSafeArea()
        }
    }

    private func openCamera() {
        guard ProfileChangeRequestPhotoCamera.isCameraAvailable else {
            errorMessage = sourceMode == .cameraOnly
                ? AppLanguageManager.localized("verificationUpload.error.cameraRequiredForIC")
                : AppLanguageManager.localized("verificationUpload.error.cameraUnavailableUsePhotosFiles")
            return
        }
        isUsingCamera = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = AppLanguageManager.localized("verificationUpload.error.readPhoto")
                return
            }

            let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
            let fileExtension = type.preferredFilenameExtension ?? "jpg"
            attachment = .photo(
                data: data,
                fileName: "\(UUID().uuidString).\(fileExtension)",
                contentType: type.preferredMIMEType ?? "image/jpeg",
                source: .photos
            )
            errorMessage = nil
        } catch {
            errorMessage = String.localizedStringWithFormat(AppLanguageManager.localized("verificationUpload.error.readPhotoFormat"), error.localizedDescription)
        }
    }

    private func loadCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = AppLanguageManager.localized("verificationUpload.error.readCameraPhoto")
            return
        }

        attachment = .photo(data: data, fileName: "\(UUID().uuidString).jpg", contentType: "image/jpeg", source: .camera)
        errorMessage = nil
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "pdf":
            return "application/pdf"
        default:
            return "application/octet-stream"
        }
    }
}

private struct ProfileChangeRequestPhotoCamera: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private struct EditProfileMapCityRow: View {
    let title: String
    let value: String
    let actionTitle: String
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(value.isEmpty ? AppLanguageManager.localized("editProfile.common.notAdded") : value)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(value.isEmpty ? .secondary : .primary)
                }

                Spacer()
            }

            Button {
                onSearch()
            } label: {
                Label(actionTitle, systemImage: "map")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.pink)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
    }
}

private struct EditProfileOption<Value: Hashable>: Hashable {
    let value: Value
    let title: String
}

private struct EditProfileOptionMenuField<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [EditProfileOption<Value>]
    var usesWheelPicker = false

    @State private var isShowingSelector = false

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("editProfile.common.notAdded")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Button {
                HapticManager.light()
                isShowingSelector = true
            } label: {
                HStack(spacing: 10) {
                    Text(selectedTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingSelector) {
                EditProfileOptionSheet(
                    title: title,
                    selection: $selection,
                    options: options,
                    usesWheelPicker: usesWheelPicker
                )
                .presentationDetents(usesWheelPicker ? [.height(360)] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
    }
}

private struct EditProfileOptionSheet<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [EditProfileOption<Value>]
    let usesWheelPicker: Bool

    @Environment(\.dismiss) private var dismiss

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("editProfile.common.notAdded")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                sheetHeader

                if usesWheelPicker {
                    Picker(title, selection: $selection) {
                        ForEach(options, id: \.self) { option in
                            Text(option.title)
                                .tag(option.value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)

                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Text(AppLanguageManager.localized("common.done"))
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(options, id: \.self) { option in
                                Button {
                                    HapticManager.light()
                                    selection = option.value
                                    dismiss()
                                } label: {
                                    EditProfileOptionSheetRow(
                                        title: option.title,
                                        isSelected: option.value == selection
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                }
            }
            .padding(.top, 14)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguageManager.localized("common.close")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var sheetHeader: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(selectedTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.pink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.pink.opacity(0.09), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}

private struct EditProfileOptionSheetRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSelected ? .pink : .secondary.opacity(0.35))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.pink.opacity(0.24) : Color.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.035), radius: isSelected ? 10 : 6, y: 4)
    }
}

private struct EditProfileStringPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        EditProfileOptionMenuField(
            title: title,
            selection: $selection,
            options: options.map { option in
                EditProfileOption(value: option, title: option.isEmpty ? AppLanguageManager.localized("editProfile.common.notAdded") : LocalizedProfileDisplay.option(option))
            }
        )
    }
}

private struct EditProfileReadonlyField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
    }
}

private struct EditProfileMultiSelectField: View {
    let title: String
    @Binding var selectionText: String
    let options: [String]
    let maxSelection: Int
    var displayTitle: (String) -> String = { LocalizedProfileDisplay.option($0) }

    @State private var message: String?

    private var selectedValues: [String] {
        selectionText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(selectedValues.count)/\(maxSelection)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.pink)
            }

            if let message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    InterestTagChip(
                        title: localizedDisplayTitle(for: option),
                        isSelected: selectedValues.contains(option)
                    ) {
                        toggle(option)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
    }

    private func localizedDisplayTitle(for option: String) -> String {
        let normalized = option.uppercased()

        let mbtiOptions: Set<String> = [
            "INTJ", "INTP", "ENTJ", "ENTP",
            "INFJ", "INFP", "ENFJ", "ENFP",
            "ISTJ", "ISFJ", "ESTJ", "ESFJ",
            "ISTP", "ISFP", "ESTP", "ESFP"
        ]

        if mbtiOptions.contains(normalized) {
            return normalized
        }

        return displayTitle(option)
    }

    private func toggle(_ option: String) {
        message = nil
        var values = selectedValues

        if values.contains(option) {
            values.removeAll { $0 == option }
        } else {
            guard values.count < maxSelection else {
                message = String(format: AppLanguageManager.localized("editProfile.multiSelect.maxSelectionFormat"), maxSelection)
                return
            }

            values.append(option)
        }

        selectionText = values.joined(separator: ", ")
    }
}

private struct InlineCompletionHint: View {
    let isComplete: Bool
    let completeText: String
    let incompleteText: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(isComplete ? .green : .secondary)
                .padding(.top, 1)

            Text(isComplete ? completeText : incompleteText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct EditProfileSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.pink, Color.pink.opacity(0.42)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 34)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

private struct EditProfileGuidanceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.pink, in: Circle())

                Text(AppLanguageManager.localized("editProfile.guidance.title"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }

            Text(AppLanguageManager.localized("editProfile.guidance.message"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.pink.opacity(0.075)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.pink.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }
}

private struct CitySelectorView: View {
    let title: String
    @Binding var selectedCity: String

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let cities = [
        "Kuala Lumpur", "Petaling Jaya", "Subang Jaya", "Shah Alam", "Klang", "Ampang", "Cheras", "Puchong", "Cyberjaya", "Putrajaya", "Kajang", "Bangi", "Semenyih", "Rawang", "Selayang", "Gombak",
        "George Town", "Bayan Lepas", "Butterworth", "Bukit Mertajam", "Perai", "Sungai Petani", "Alor Setar", "Kulim", "Jitra", "Langkawi",
        "Ipoh", "Taiping", "Teluk Intan", "Kampar", "Sitiawan", "Lumut", "Batu Gajah", "Kuala Kangsar",
        "Johor Bahru", "Iskandar Puteri", "Skudai", "Kulai", "Batu Pahat", "Muar", "Kluang", "Segamat", "Pontian", "Mersing",
        "Melaka", "Ayer Keroh", "Seremban", "Nilai", "Port Dickson", "Bahau",
        "Kuantan", "Temerloh", "Bentong", "Raub", "Genting Highlands", "Cameron Highlands",
        "Kota Bharu", "Kuala Terengganu", "Dungun", "Kemaman", "Kerteh",
        "Kota Kinabalu", "Sandakan", "Tawau", "Lahad Datu", "Keningau", "Kuching", "Miri", "Sibu", "Bintulu", "Sri Aman", "Labuan"
    ]

    private var filteredCities: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cities }

        return cities.filter { city in
            city.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !cities.contains(where: { $0.caseInsensitiveCompare(searchText) == .orderedSame }) {
                    Button {
                        selectedCity = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(String(format: AppLanguageManager.localized("citySelector.useCustomCityFormat"), searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
                            Text(AppLanguageManager.localized("citySelector.addAsCustomCity"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(filteredCities, id: \.self) { city in
                    Button {
                        selectedCity = city
                        dismiss()
                    } label: {
                        HStack {
                            Text(city)
                            Spacer()
                            if city == selectedCity {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $searchText, prompt: AppLanguageManager.localized("citySelector.searchPrompt"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfilePromptEditorView: View {
    @Binding var prompts: [ProfilePrompt]
    let userId: UUID?

    private let maxPrompts = 3
    private var promptOptions: [EditProfileOption<String>] {
        [
            EditProfileOption(value: "A green flag I look for is...", title: AppLanguageManager.localized("profilePrompt.greenFlag")),
            EditProfileOption(value: "My ideal relationship feels like...", title: AppLanguageManager.localized("profilePrompt.idealRelationship")),
            EditProfileOption(value: "Sunday usually means...", title: AppLanguageManager.localized("profilePrompt.sundayUsuallyMeans")),
            EditProfileOption(value: "The way to win me over is...", title: AppLanguageManager.localized("profilePrompt.winMeOver")),
            EditProfileOption(value: "One thing people misunderstand about me is...", title: AppLanguageManager.localized("profilePrompt.misunderstood")),
            EditProfileOption(value: "I am happiest when...", title: AppLanguageManager.localized("profilePrompt.happiestWhen")),
            EditProfileOption(value: "My perfect weekend includes...", title: AppLanguageManager.localized("profilePrompt.perfectWeekend")),
            EditProfileOption(value: "A small thing I appreciate is...", title: AppLanguageManager.localized("profilePrompt.smallThingIAppreciate")),
            EditProfileOption(value: "I feel most connected when...", title: AppLanguageManager.localized("profilePrompt.feelConnected")),
            EditProfileOption(value: "Together, I would love to...", title: AppLanguageManager.localized("profilePrompt.togetherLoveTo")),
            EditProfileOption(value: "The best way to support me is...", title: AppLanguageManager.localized("profilePrompt.supportMe")),
            EditProfileOption(value: "A value I live by is...", title: AppLanguageManager.localized("profilePrompt.valueILiveBy")),
            EditProfileOption(value: "I will always make time for...", title: AppLanguageManager.localized("profilePrompt.makeTimeFor")),
            EditProfileOption(value: "My simple joy is...", title: AppLanguageManager.localized("profilePrompt.simpleJoy")),
            EditProfileOption(value: "A date I would never forget is...", title: AppLanguageManager.localized("profilePrompt.unforgettableDate")),
            EditProfileOption(value: "I know I like someone when...", title: AppLanguageManager.localized("profilePrompt.knowILikeSomeone"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prompts.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.pink)
                        .padding(.top, 2)

                    Text(AppLanguageManager.localized("editProfile.prompts.empty.message"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ForEach($prompts) { $prompt in
                ProfilePromptRow(
                    prompt: $prompt,
                    promptOptions: promptOptions,
                    onDelete: {
                        prompts.removeAll { $0.id == prompt.id }
                    }
                )
            }

            if prompts.count < maxPrompts {
                Button {
                    addPrompt()
                } label: {
                    Label(AppLanguageManager.localized("editProfile.prompts.addPrompt"), systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
            }
        }
        .padding(.vertical, 4)
    }

    private func addPrompt() {
        guard let userId, prompts.count < maxPrompts else { return }

        prompts.append(
            ProfilePrompt(
                id: UUID(),
                userId: userId,
                prompt: promptOptions.first?.value ?? "",
                answer: "",
                displayOrder: prompts.count,
                createdAt: nil,
                updatedAt: nil
            )
        )
    }
}

private struct ProfilePromptRow: View {
    @Binding var prompt: ProfilePrompt
    let promptOptions: [EditProfileOption<String>]
    let onDelete: () -> Void

    @State private var isShowingPromptOptions = false

    private var selectedPromptTitle: String {
        promptOptions.first(where: { $0.value == prompt.prompt })?.title ?? prompt.prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                promptSelector

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguageManager.localized("editProfile.prompts.removePrompt"))
            }

            TextField(AppLanguageManager.localized("editProfile.prompts.answerPlaceholder"), text: $prompt.answer, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2...5)
                .padding(12)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .sheet(isPresented: $isShowingPromptOptions) {
            EditProfileOptionSheet(
                title: AppLanguageManager.localized("editProfile.prompts.choosePrompt"),
                selection: $prompt.prompt,
                options: promptOptions,
                usesWheelPicker: false
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var promptSelector: some View {
        Button {
            isShowingPromptOptions = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguageManager.localized("editProfile.prompts.promptLabel"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 8) {
                    Text(selectedPromptTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct InterestTagPickerView: View {
    @Binding var selectedInterests: [String]
    @Binding var message: String?

    private let maxSelection = 5
    private var categories: [InterestCategory] {
        [
            InterestCategory(
                title: AppLanguageManager.localized("interest.category.foodDrinks"),
                interests: [
                    EditProfileOption(value: "Coffee", title: AppLanguageManager.localized("interest.coffee")),
                    EditProfileOption(value: "Cafe Hopping", title: AppLanguageManager.localized("interest.cafeHopping")),
                    EditProfileOption(value: "Foodie", title: AppLanguageManager.localized("interest.foodie")),
                    EditProfileOption(value: "Cooking", title: AppLanguageManager.localized("interest.cooking")),
                    EditProfileOption(value: "Baking", title: AppLanguageManager.localized("interest.baking")),
                    EditProfileOption(value: "Desserts", title: AppLanguageManager.localized("interest.desserts")),
                    EditProfileOption(value: "Tea", title: AppLanguageManager.localized("interest.tea")),
                    EditProfileOption(value: "Brunch", title: AppLanguageManager.localized("interest.brunch"))
                ]
            ),
            InterestCategory(
                title: AppLanguageManager.localized("interest.category.activeLifestyle"),
                interests: [
                    EditProfileOption(value: "Gym", title: AppLanguageManager.localized("interest.gym")),
                    EditProfileOption(value: "Running", title: AppLanguageManager.localized("interest.running")),
                    EditProfileOption(value: "Hiking", title: AppLanguageManager.localized("interest.hiking")),
                    EditProfileOption(value: "Yoga", title: AppLanguageManager.localized("interest.yoga")),
                    EditProfileOption(value: "Cycling", title: AppLanguageManager.localized("interest.cycling")),
                    EditProfileOption(value: "Swimming", title: AppLanguageManager.localized("interest.swimming")),
                    EditProfileOption(value: "Badminton", title: AppLanguageManager.localized("interest.badminton")),
                    EditProfileOption(value: "Football", title: AppLanguageManager.localized("interest.football")),
                    EditProfileOption(value: "Dancing", title: AppLanguageManager.localized("interest.dancing"))
                ]
            ),
            InterestCategory(
                title: AppLanguageManager.localized("interest.category.creativeCulture"),
                interests: [
                    EditProfileOption(value: "Music", title: AppLanguageManager.localized("interest.music")),
                    EditProfileOption(value: "Movies", title: AppLanguageManager.localized("interest.movies")),
                    EditProfileOption(value: "Books", title: AppLanguageManager.localized("interest.books")),
                    EditProfileOption(value: "Art", title: AppLanguageManager.localized("interest.art")),
                    EditProfileOption(value: "Photography", title: AppLanguageManager.localized("interest.photography")),
                    EditProfileOption(value: "Concerts", title: AppLanguageManager.localized("interest.concerts")),
                    EditProfileOption(value: "Museums", title: AppLanguageManager.localized("interest.museums")),
                    EditProfileOption(value: "Karaoke", title: AppLanguageManager.localized("interest.karaoke")),
                    EditProfileOption(value: "Fashion", title: AppLanguageManager.localized("interest.fashion"))
                ]
            ),
            InterestCategory(
                title: AppLanguageManager.localized("interest.category.homePersonality"),
                interests: [
                    EditProfileOption(value: "Pets", title: AppLanguageManager.localized("interest.pets")),
                    EditProfileOption(value: "Night Owl", title: AppLanguageManager.localized("interest.nightOwl")),
                    EditProfileOption(value: "Early Bird", title: AppLanguageManager.localized("interest.earlyBird")),
                    EditProfileOption(value: "Family-Oriented", title: AppLanguageManager.localized("interest.familyOriented")),
                    EditProfileOption(value: "Career-Focused", title: AppLanguageManager.localized("interest.careerFocused")),
                    EditProfileOption(value: "Skincare", title: AppLanguageManager.localized("interest.skincare")),
                    EditProfileOption(value: "Spirituality", title: AppLanguageManager.localized("interest.spirituality")),
                    EditProfileOption(value: "Volunteering", title: AppLanguageManager.localized("interest.volunteering"))
                ]
            ),
            InterestCategory(
                title: AppLanguageManager.localized("interest.category.funExploration"),
                interests: [
                    EditProfileOption(value: "Travel", title: AppLanguageManager.localized("interest.travel")),
                    EditProfileOption(value: "Nature", title: AppLanguageManager.localized("interest.nature")),
                    EditProfileOption(value: "Beach", title: AppLanguageManager.localized("interest.beach")),
                    EditProfileOption(value: "Road Trips", title: AppLanguageManager.localized("interest.roadTrips")),
                    EditProfileOption(value: "Gaming", title: AppLanguageManager.localized("interest.gaming")),
                    EditProfileOption(value: "Board Games", title: AppLanguageManager.localized("interest.boardGames")),
                    EditProfileOption(value: "Anime", title: AppLanguageManager.localized("interest.anime")),
                    EditProfileOption(value: "Tech", title: AppLanguageManager.localized("interest.tech")),
                    EditProfileOption(value: "Finance", title: AppLanguageManager.localized("interest.finance"))
                ]
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: AppLanguageManager.localized("editProfile.interests.chooseUpToFormat"), maxSelection))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(selectedInterests.count)/\(maxSelection)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.pink.opacity(0.09), in: Capsule())
            }

            if let message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(category.interests, id: \.self) { interest in
                            InterestTagChip(
                                title: interest.title,
                                isSelected: selectedInterests.contains(interest.value)
                            ) {
                                toggle(interest.value)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ interest: String) {
        message = nil

        if selectedInterests.contains(interest) {
            selectedInterests.removeAll { $0 == interest }
            return
        }

        guard selectedInterests.count < maxSelection else {
            message = AppLanguageManager.localized("editProfile.interests.maxSelectionMessage")
            return
        }

        selectedInterests.append(interest)
    }
}

private struct InterestCategory: Identifiable {
    let title: String
    let interests: [EditProfileOption<String>]

    var id: String { title }
}

private struct InterestTagChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isSelected ? Color.pink : Color(.tertiarySystemGroupedBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.black.opacity(0.045), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}



private struct EditProfileCardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditProfileSectionHeader(title: title, subtitle: subtitle)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemGroupedBackground).opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
        }
        .padding(.horizontal, 16)
    }
}
