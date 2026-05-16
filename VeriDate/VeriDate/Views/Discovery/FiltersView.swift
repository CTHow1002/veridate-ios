import SwiftUI

struct FiltersView: View {
    @ObservedObject var vm: DiscoveryViewModel
    let userId: UUID
    let currentProfile: Profile?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        FilterIntroCard()

                        FilterCardSection(
                            title: AppLanguageManager.localized("filters_section_who_title"),
                            subtitle: AppLanguageManager.localized("filters_section_who_subtitle")
                        ) {
                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_preferred_gender_title"),
                                icon: "person.2.fill",
                                selectedValues: $vm.preferredGenders,
                                options: GenderType.allCases.map(\.rawValue),
                                display: display
                            )

                            FilterRangeCard(
                                title: AppLanguageManager.localized("filters_age_range_title"),
                                icon: "calendar",
                                unit: AppLanguageManager.localized("filters_years_old_unit"),
                                minValue: $vm.minAge,
                                maxValue: $vm.maxAge,
                                bounds: 18...100,
                                step: 1
                            )

                            FilterRangeCard(
                                title: AppLanguageManager.localized("filters_distance_range_title"),
                                icon: "location.fill",
                                unit: AppLanguageManager.localized("filters_km_unit"),
                                minValue: $vm.minDistanceKm,
                                maxValue: $vm.maxDistanceKm,
                                bounds: 0...200,
                                step: 5
                            )

                            FilterRangeCard(
                                title: AppLanguageManager.localized("filters_height_range_title"),
                                icon: "ruler.fill",
                                unit: AppLanguageManager.localized("filters_cm_unit"),
                                minValue: $vm.minHeightCm,
                                maxValue: $vm.maxHeightCm,
                                bounds: 120...220,
                                step: 1
                            )
                        }

                        FilterCardSection(
                            title: AppLanguageManager.localized("filters_section_lifestyle_title"),
                            subtitle: AppLanguageManager.localized("filters_section_lifestyle_subtitle")
                        ) {
                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_marital_status_title"),
                                icon: "person.2.fill",
                                selectedValues: $vm.maritalStatuses,
                                options: MaritalStatus.allCases.map(\.rawValue),
                                display: display
                            )

                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_race_title"),
                                icon: "person.text.rectangle.fill",
                                selectedValues: $vm.races,
                                options: FilterOptionSets.races,
                                display: display
                            )

                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_religion_title"),
                                icon: "sparkles",
                                selectedValues: $vm.religions,
                                options: FilterOptionSets.religions,
                                display: display
                            )

                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_education_title"),
                                icon: "graduationcap.fill",
                                selectedValues: $vm.educationLevels,
                                options: ProfileSetupViewModel.educationLevels,
                                display: display
                            )

                            FilterMultiSelectCard(
                                title: AppLanguageManager.localized("filters_relationship_goal_title"),
                                icon: "heart.fill",
                                selectedValues: $vm.relationshipGoals,
                                options: RelationshipIntention.allCases.map(\.rawValue),
                                display: display
                            )
                        }

                        FilterCardSection(
                            title: AppLanguageManager.localized("filters_section_daily_life_title"),
                            subtitle: AppLanguageManager.localized("filters_section_daily_life_subtitle")
                        ) {
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_smoking_title"), icon: "smoke.fill", selectedValues: $vm.smokingOptions, options: FilterOptionSets.smoking, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_drinking_title"), icon: "wineglass.fill", selectedValues: $vm.drinkingOptions, options: FilterOptionSets.drinking, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_exercise_title"), icon: "figure.run", selectedValues: $vm.exerciseOptions, options: FilterOptionSets.exercise, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_pets_title"), icon: "pawprint.fill", selectedValues: $vm.petOptions, options: FilterOptionSets.pets, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_communication_title"), icon: "bubble.left.and.bubble.right.fill", selectedValues: $vm.communicationStyles, options: FilterOptionSets.communicationStyles, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_love_language_title"), icon: "heart.text.square.fill", selectedValues: $vm.loveLanguages, options: FilterOptionSets.loveLanguages, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_mbti_title"), icon: "brain.head.profile", selectedValues: $vm.mbtis, options: FilterOptionSets.mbtis, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_languages_title"), icon: "character.bubble.fill", selectedValues: $vm.languageOptions, options: FilterOptionSets.languages, display: display)
                            FilterMultiSelectCard(title: AppLanguageManager.localized("filters_family_plans_title"), icon: "figure.2.and.child.holdinghands", selectedValues: $vm.familyPlansOptions, options: FilterOptionSets.familyPlans, display: display)
                        }

                        FilterCardSection(
                            title: AppLanguageManager.localized("filters_section_trust_title"),
                            subtitle: AppLanguageManager.localized("filters_section_trust_subtitle")
                        ) {
                            VerifiedOnlyCard()
                        }

                        Button {
                            resetFilters()
                        } label: {
                            Label(AppLanguageManager.localized("filters_reset_button"), systemImage: "arrow.counterclockwise")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.pink)
                        .padding(.horizontal, 16)
                        .accessibilityLabel(AppLanguageManager.localized("filters_reset_button"))

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(AppLanguageManager.localized("filters_navigation_title"))
            .tint(.pink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguageManager.localized("common_cancel")) {
                        onDone()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let saved = await vm.saveFilters(userId: userId)
                            if saved {
                                await vm.loadFilters(userId: userId)
                                await vm.loadProfiles(userId: userId, currentProfile: currentProfile)
                                onDone()
                            }
                        }
                    } label: {
                        if vm.isSavingFilters {
                            ProgressView()
                                .accessibilityHidden(true)
                        } else {
                            Text(AppLanguageManager.localized("common_save"))
                        }
                    }
                    .disabled(vm.isSavingFilters)
                    .accessibilityLabel(AppLanguageManager.localized("common_save"))
                }
            }
        }
    }

    private var preferredGenderBinding: Binding<String> {
        Binding(
            get: { vm.preferredGender?.rawValue ?? "" },
            set: { newValue in
                vm.preferredGender = newValue.isEmpty ? nil : GenderType(rawValue: newValue)
            }
        )
    }

    private var relationshipGoalBinding: Binding<String> {
        Binding(
            get: { vm.relationshipGoal?.rawValue ?? "" },
            set: { newValue in
                vm.relationshipGoal = newValue.isEmpty ? nil : RelationshipIntention(rawValue: newValue)
            }
        )
    }

    private func display(_ value: String) -> String {
        localizedFilterOption(value)
    }

    private func resetFilters() {
        vm.preferredGender = nil
        vm.preferredGenders = []
        vm.minAge = 18
        vm.maxAge = 50
        vm.minDistanceKm = 0
        vm.maxDistanceKm = 100
        vm.minHeightCm = 120
        vm.maxHeightCm = 200
        vm.educationLevel = ""
        vm.relationshipGoal = nil
        vm.maritalStatuses = []
        vm.races = []
        vm.religions = []
        vm.educationLevels = []
        vm.relationshipGoals = []
        vm.smokingOptions = []
        vm.drinkingOptions = []
        vm.exerciseOptions = []
        vm.petOptions = []
        vm.communicationStyles = []
        vm.loveLanguages = []
        vm.mbtis = []
        vm.languageOptions = []
        vm.familyPlansOptions = []
    }
}

private enum FilterOptionSets {
    static let races = ["Malay", "Chinese", "Indian", "Iban", "Kadazan", "Mixed", "Other"]
    static let religions = ["Islam", "Buddhism", "Christianity", "Hinduism", "Taoism", "Atheist", "Agnostic", "Spiritual", "Other"]
    static let smoking = ["Never", "Socially", "Sometimes", "Often"]
    static let drinking = ["Never", "Socially", "Sometimes", "Often"]
    static let exercise = ["Daily", "A few times a week", "Sometimes", "Rarely"]
    static let pets = ["Dog", "Cat", "Fish", "Bird", "Rabbit", "Hamster", "Reptile", "Have pets", "Want pets", "No pet but love them", "Not a pet person", "Allergic to pets"]
    static let communicationStyles = ["Responsive texter", "Thoughtful texter", "Phone calls", "Video calls", "Voice messages", "In-person conversations", "Plans ahead", "Spontaneous check-ins", "Low-maintenance communicator"]
    static let loveLanguages = ["Quality time", "Words of affirmation", "Acts of service", "Physical touch", "Receiving gifts", "Not sure yet"]
    static let mbtis = ["ISTJ", "ISFJ", "INFJ", "INTJ", "ISTP", "ISFP", "INFP", "INTP", "ESTP", "ESFP", "ENFP", "ENTP", "ESTJ", "ESFJ", "ENFJ", "ENTJ", "NOT SURE"]
    static let languages = ["English", "Malay", "Mandarin", "Cantonese", "Tamil", "Hokkien", "Hakka", "Teochew", "Japanese", "Korean", "Arabic", "Hindi", "Indonesian", "Thai", "Other"]
    static let familyPlans = ["Want children", "Open to children", "Do not want children", "Have children"]
}

private func localizedFilterOption(_ value: String) -> String {
    if FilterOptionSets.mbtis.contains(value) {
        return value.uppercased()
    }

    return LocalizedProfileDisplay.option(value)
}

private func legacyLocalizedFilterOption(_ value: String) -> String {
    switch value {
    case "male":
        return AppLanguageManager.localized("gender.male")
    case "female":
        return AppLanguageManager.localized("gender.female")
    case "non_binary":
        return AppLanguageManager.localized("gender.nonBinary")
    case "single":
        return AppLanguageManager.localized("maritalStatus.single")
    case "divorced":
        return AppLanguageManager.localized("maritalStatus.divorced")
    case "widowed":
        return AppLanguageManager.localized("maritalStatus.widowed")
    case "separated":
        return AppLanguageManager.localized("maritalStatus.separated")
    case "prefer_not_to_say":
        return AppLanguageManager.localized("maritalStatus.preferNotToSay")
    case "serious_relationship":
        return AppLanguageManager.localized("relationshipGoal.seriousRelationship")
    case "life_partner":
        return AppLanguageManager.localized("relationshipGoal.lifePartner")
    case "marriage":
        return AppLanguageManager.localized("relationshipGoal.marriage")
    case "long_term":
        return AppLanguageManager.localized("relationshipGoal.longTerm")
    case "short_term":
        return AppLanguageManager.localized("relationshipGoal.shortTerm")
    case "friendship":
        return AppLanguageManager.localized("relationshipGoal.friendship")
    case "still_figuring_out":
        return AppLanguageManager.localized("relationshipGoal.stillFiguringOut")
    case "Primary School":
        return AppLanguageManager.localized("filterOption.education.primarySchool")
    case "Secondary School":
        return AppLanguageManager.localized("filterOption.education.secondarySchool")
    case "High School":
        return AppLanguageManager.localized("filterOption.education.highSchool")
    case "SPM":
        return AppLanguageManager.localized("filterOption.education.spm")
    case "STPM":
        return AppLanguageManager.localized("filterOption.education.stpm")
    case "A-Level":
        return AppLanguageManager.localized("filterOption.education.aLevel")
    case "Foundation":
        return AppLanguageManager.localized("filterOption.education.foundation")
    case "Diploma":
        return AppLanguageManager.localized("filterOption.education.diploma")
    case "Advanced Diploma":
        return AppLanguageManager.localized("filterOption.education.advancedDiploma")
    case "Degree":
        return AppLanguageManager.localized("filterOption.education.degree")
    case "Bachelor's Degree":
        return AppLanguageManager.localized("filterOption.education.bachelorsDegree")
    case "Master":
        return AppLanguageManager.localized("filterOption.education.master")
    case "Master's Degree":
        return AppLanguageManager.localized("filterOption.education.mastersDegree")
    case "PhD":
        return AppLanguageManager.localized("filterOption.education.phd")
    case "Doctorate":
        return AppLanguageManager.localized("filterOption.education.doctorate")
    case "Professional Degree":
        return AppLanguageManager.localized("filterOption.education.professionalDegree")
    case "Malay":
        return AppLanguageManager.localized("filterOption.common.malay")
    case "Chinese":
        return AppLanguageManager.localized("filterOption.race.chinese")
    case "Indian":
        return AppLanguageManager.localized("filterOption.race.indian")
    case "Iban":
        return AppLanguageManager.localized("filterOption.race.iban")
    case "Kadazan":
        return AppLanguageManager.localized("filterOption.race.kadazan")
    case "Mixed":
        return AppLanguageManager.localized("filterOption.race.mixed")
    case "Other":
        return AppLanguageManager.localized("filterOption.common.other")
    case "Islam":
        return AppLanguageManager.localized("filterOption.religion.islam")
    case "Buddhism":
        return AppLanguageManager.localized("filterOption.religion.buddhism")
    case "Christianity":
        return AppLanguageManager.localized("filterOption.religion.christianity")
    case "Hinduism":
        return AppLanguageManager.localized("filterOption.religion.hinduism")
    case "Taoism":
        return AppLanguageManager.localized("filterOption.religion.taoism")
    case "Atheist":
        return AppLanguageManager.localized("filterOption.religion.atheist")
    case "Agnostic":
        return AppLanguageManager.localized("filterOption.religion.agnostic")
    case "Spiritual":
        return AppLanguageManager.localized("filterOption.religion.spiritual")
    case "Never":
        return AppLanguageManager.localized("filterOption.frequency.never")
    case "Socially":
        return AppLanguageManager.localized("filterOption.frequency.socially")
    case "Sometimes":
        return AppLanguageManager.localized("filterOption.frequency.sometimes")
    case "Often":
        return AppLanguageManager.localized("filterOption.frequency.often")
    case "Daily":
        return AppLanguageManager.localized("filterOption.frequency.daily")
    case "A few times a week":
        return AppLanguageManager.localized("filterOption.exercise.fewTimesAWeek")
    case "Rarely":
        return AppLanguageManager.localized("filterOption.frequency.rarely")
    case "Dog":
        return AppLanguageManager.localized("filterOption.pet.dog")
    case "Cat":
        return AppLanguageManager.localized("filterOption.pet.cat")
    case "Fish":
        return AppLanguageManager.localized("filterOption.pet.fish")
    case "Bird":
        return AppLanguageManager.localized("filterOption.pet.bird")
    case "Rabbit":
        return AppLanguageManager.localized("filterOption.pet.rabbit")
    case "Hamster":
        return AppLanguageManager.localized("filterOption.pet.hamster")
    case "Reptile":
        return AppLanguageManager.localized("filterOption.pet.reptile")
    case "Have pets":
        return AppLanguageManager.localized("filterOption.pet.havePets")
    case "Want pets":
        return AppLanguageManager.localized("filterOption.pet.wantPets")
    case "No pet but love them":
        return AppLanguageManager.localized("filterOption.pet.noPetButLoveThem")
    case "Not a pet person":
        return AppLanguageManager.localized("filterOption.pet.notPetPerson")
    case "Allergic to pets":
        return AppLanguageManager.localized("filterOption.pet.allergic")
    case "Responsive texter":
        return AppLanguageManager.localized("filterOption.communication.responsiveTexter")
    case "Thoughtful texter":
        return AppLanguageManager.localized("filterOption.communication.thoughtfulTexter")
    case "Phone calls":
        return AppLanguageManager.localized("filterOption.communication.phoneCalls")
    case "Video calls":
        return AppLanguageManager.localized("filterOption.communication.videoCalls")
    case "Voice messages":
        return AppLanguageManager.localized("filterOption.communication.voiceMessages")
    case "In-person conversations":
        return AppLanguageManager.localized("filterOption.communication.inPerson")
    case "Plans ahead":
        return AppLanguageManager.localized("filterOption.communication.plansAhead")
    case "Spontaneous check-ins":
        return AppLanguageManager.localized("filterOption.communication.spontaneousCheckIns")
    case "Low-maintenance communicator":
        return AppLanguageManager.localized("filterOption.communication.lowMaintenance")
    case "Quality time":
        return AppLanguageManager.localized("filterOption.loveLanguage.qualityTime")
    case "Words of affirmation":
        return AppLanguageManager.localized("filterOption.loveLanguage.wordsOfAffirmation")
    case "Acts of service":
        return AppLanguageManager.localized("filterOption.loveLanguage.actsOfService")
    case "Physical touch":
        return AppLanguageManager.localized("filterOption.loveLanguage.physicalTouch")
    case "Receiving gifts":
        return AppLanguageManager.localized("filterOption.loveLanguage.receivingGifts")
    case "Not sure yet":
        return AppLanguageManager.localized("filterOption.common.notSureYet")
    case "Not sure":
        return AppLanguageManager.localized("filterOption.common.notSure")
    case "English":
        return AppLanguageManager.localized("filterOption.language.english")
    case "Mandarin":
        return AppLanguageManager.localized("filterOption.language.mandarin")
    case "Cantonese":
        return AppLanguageManager.localized("filterOption.language.cantonese")
    case "Tamil":
        return AppLanguageManager.localized("filterOption.language.tamil")
    case "Hokkien":
        return AppLanguageManager.localized("filterOption.language.hokkien")
    case "Hakka":
        return AppLanguageManager.localized("filterOption.language.hakka")
    case "Teochew":
        return AppLanguageManager.localized("filterOption.language.teochew")
    case "Japanese":
        return AppLanguageManager.localized("filterOption.language.japanese")
    case "Korean":
        return AppLanguageManager.localized("filterOption.language.korean")
    case "Arabic":
        return AppLanguageManager.localized("filterOption.language.arabic")
    case "Hindi":
        return AppLanguageManager.localized("filterOption.language.hindi")
    case "Indonesian":
        return AppLanguageManager.localized("filterOption.language.indonesian")
    case "Thai":
        return AppLanguageManager.localized("filterOption.language.thai")
    case "Want children":
        return AppLanguageManager.localized("filterOption.familyPlans.wantChildren")
    case "Open to children":
        return AppLanguageManager.localized("filterOption.familyPlans.openToChildren")
    case "Do not want children":
        return AppLanguageManager.localized("filterOption.familyPlans.doNotWantChildren")
    case "Have children":
        return AppLanguageManager.localized("filterOption.familyPlans.haveChildren")
    default:
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct FilterIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.pink, in: Circle())
                    .accessibilityHidden(true)

                Text(AppLanguageManager.localized("filters_intro_title"))
                    .font(.title3.weight(.bold))
            }

            Text(AppLanguageManager.localized("filters_intro_message"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.pink.opacity(0.075)],
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
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

private struct FilterCardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.bold))

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemGroupedBackground).opacity(0.42)],
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

private struct FilterPickerField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct VerifiedOnlyCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 34, height: 34)
                .background(Color.green.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguageManager.localized("filters_verified_only_title"))
                    .font(.subheadline.weight(.semibold))

                Text(AppLanguageManager.localized("filters_verified_only_message"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FilterMultiSelectCard: View {
    let title: String
    let icon: String
    @Binding var selectedValues: [String]
    let options: [String]
    let display: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.pink)
                    .frame(width: 28, height: 28)
                    .background(Color.pink.opacity(0.09), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(selectedValues.isEmpty ? AppLanguageManager.localized("common_any") : String.localizedStringWithFormat(AppLanguageManager.localized("filters_selected_count_format"), selectedValues.count))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(.systemBackground), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    FilterChip(
                        title: display(option),
                        isSelected: selectedValues.contains(option)
                    ) {
                        toggle(option)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ option: String) {
        if selectedValues.contains(option) {
            selectedValues.removeAll { $0 == option }
        } else {
            selectedValues.append(option)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.pink : Color(.systemBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.black.opacity(0.045), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? AppLanguageManager.localized("filters_option_selected") : AppLanguageManager.localized("filters_option_not_selected"))
    }
}

private struct FilterRangeCard: View {
    let title: String
    let icon: String
    let unit: String
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let bounds: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityElement(children: .combine)

                Spacer()

                Text(String.localizedStringWithFormat(AppLanguageManager.localized("filters_range_value_format"), min(minValue, maxValue), max(minValue, maxValue), unit))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(.systemBackground), in: Capsule())
            }

            RangeSlider(
                minValue: $minValue,
                maxValue: $maxValue,
                bounds: bounds,
                step: step,
                unit: unit
            )
        }
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.035), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RangeSlider: View {
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let bounds: ClosedRange<Int>
    let step: Int
    let unit: String

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - thumbSize, 1)
            let minX = xPosition(for: minValue, width: width)
            let maxX = xPosition(for: maxValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: trackHeight)
                    .offset(x: thumbSize / 2)
                    .accessibilityHidden(true)

                Capsule()
                    .fill(.tint)
                    .frame(width: max(maxX - minX, 0), height: trackHeight)
                    .offset(x: minX + thumbSize / 2)
                    .accessibilityHidden(true)

                thumb
                    .offset(x: minX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                minValue = snappedValue(for: value.location.x - thumbSize / 2, width: width)
                                if minValue > maxValue {
                                    minValue = maxValue
                                }
                            }
                    )
                    .accessibilityLabel(AppLanguageManager.localized("filters_minimum_accessibility_label"))
                    .accessibilityValue(String.localizedStringWithFormat(AppLanguageManager.localized("filters_slider_value_format"), minValue, unit))

                thumb
                    .offset(x: maxX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                maxValue = snappedValue(for: value.location.x - thumbSize / 2, width: width)
                                if maxValue < minValue {
                                    maxValue = minValue
                                }
                            }
                    )
                    .accessibilityLabel(AppLanguageManager.localized("filters_maximum_accessibility_label"))
                    .accessibilityValue(String.localizedStringWithFormat(AppLanguageManager.localized("filters_slider_value_format"), maxValue, unit))
            }
            .frame(height: thumbSize)
        }
        .frame(height: 36)
    }

    private var thumb: some View {
        Circle()
            .fill(.background)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .overlay {
                Circle()
                    .stroke(.tint, lineWidth: 2)
                    .accessibilityHidden(true)
            }
    }

    private func xPosition(for value: Int, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        let percent = CGFloat(clamped - bounds.lowerBound) / CGFloat(bounds.upperBound - bounds.lowerBound)
        return percent * width
    }

    private func snappedValue(for xPosition: CGFloat, width: CGFloat) -> Int {
        let percent = min(max(xPosition / width, 0), 1)
        let rawValue = Double(bounds.lowerBound) + Double(percent) * Double(bounds.upperBound - bounds.lowerBound)
        let steppedValue = (rawValue / Double(step)).rounded() * Double(step)
        return min(max(Int(steppedValue), bounds.lowerBound), bounds.upperBound)
    }
}
