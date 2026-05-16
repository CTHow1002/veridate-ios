import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ProfileSetupViewModel()
    var onCompleted: (() -> Void)?

    @State private var step: ProfileSetupStep = .name
    @State private var hometown = ""
    @State private var currentlyLiving = ""
    @State private var showingHometownSelector = false
    @State private var showingCurrentlyLivingSelector = false
    @State private var photos: [ProfilePhoto] = []
    @State private var isLoadingPhotos = false
    @State private var hasHydratedProfile = false

    init(startsAtLastStep: Bool = false, onCompleted: (() -> Void)? = nil) {
        self.onCompleted = onCompleted
        _step = State(initialValue: startsAtLastStep ? .moreDetails : .name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ProfileSetupProgressHeader(step: step)

                    ScrollView {
                        VStack(spacing: 18) {
                            currentStepContent
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 110)
                    }
                }

                VStack {
                    Spacer()
                    ProfileSetupFooter(
                        step: step,
                        isSaving: vm.isSaving,
                        onBack: goBack,
                        onNext: {
                            Task {
                                await goNext()
                            }
                        }
                    )
                }
            }
            .navigationTitle(AppLanguageManager.localized("profileSetup.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(.pink)
            .task {
                hydrateFromCurrentProfileIfNeeded()
                await loadPhotos()
            }
            .onChange(of: session.currentProfile) { _, _ in
                hydrateFromCurrentProfileIfNeeded()
            }
            .sheet(isPresented: $showingHometownSelector) {
                MalaysiaCitySearchView(title: AppLanguageManager.localized("profileSetup.location.searchHometown"), selectedCity: $hometown)
            }
            .sheet(isPresented: $showingCurrentlyLivingSelector) {
                MalaysiaCitySearchView(title: AppLanguageManager.localized("profileSetup.location.searchCurrentCity"), selectedCity: $currentlyLiving)
            }
        }
    }

    @ViewBuilder
    private var currentStepContent: some View {
        switch step {
        case .name:
            ProfileSetupCard(
                icon: "sparkles",
                title: AppLanguageManager.localized("profileSetup.name.title"),
                subtitle: AppLanguageManager.localized("profileSetup.name.subtitle")
            ) {
                TextField(AppLanguageManager.localized("profileSetup.name.fullNamePlaceholder"), text: $vm.fullName)
                    .textContentType(.name)
                    .font(.body)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(AppLanguageManager.localized("profileSetup.name.fullNamePlaceholder"))

                TextField(AppLanguageManager.localized("profileSetup.name.displayNamePlaceholder"), text: $vm.displayName)
                    .textContentType(.nickname)
                    .font(.body)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(AppLanguageManager.localized("profileSetup.name.displayNamePlaceholder"))

                ProfileSetupHint(text: AppLanguageManager.localized("profileSetup.name.hint"))
            }

        case .basics:
            ProfileSetupCard(
                icon: "person.fill",
                title: AppLanguageManager.localized("profileSetup.basics.title"),
                subtitle: AppLanguageManager.localized("profileSetup.basics.subtitle")
            ) {
                DatePicker(
                    AppLanguageManager.localized("profileSetup.basics.dateOfBirth"),
                    selection: $vm.dateOfBirth,
                    in: vm.birthDateRange,
                    displayedComponents: .date
                )

                ProfileSetupEnumMenu(
                    title: AppLanguageManager.localized("profileSetup.basics.gender"),
                    selection: $vm.gender,
                    options: GenderType.allCases.map { gender in
                        ProfileSetupPickerOption(value: gender, title: display(gender.rawValue))
                    }
                )

                ProfileSetupEnumMenu(
                    title: AppLanguageManager.localized("profileSetup.basics.height"),
                    selection: $vm.heightCm,
                    options: (120...220).map { height in
                        ProfileSetupPickerOption(value: height, title: String.localizedStringWithFormat(AppLanguageManager.localized("profile_height_cm_format"), height))
                    },
                    usesWheelPicker: true
                )
            }

        case .photos:
            ProfileSetupCard(
                icon: "photo.on.rectangle.angled",
                title: AppLanguageManager.localized("profileSetup.photos.title"),
                subtitle: AppLanguageManager.localized("profileSetup.photos.subtitle")
            ) {
                ProfileSetupPhotoGrid(
                    photos: photos,
                    userId: session.currentUserId,
                    isLoading: isLoadingPhotos,
                    onUploaded: { uploadedPhoto in
                        await handleUploadedPhoto(uploadedPhoto)
                    },
                    onDelete: { photo in
                        Task {
                            await delete(photo)
                        }
                    }
                )

                ProfileSetupHint(text: AppLanguageManager.localized("profileSetup.photos.hint"))
            }

        case .location:
            ProfileSetupCard(
                icon: "mappin.and.ellipse",
                title: AppLanguageManager.localized("profileSetup.location.title"),
                subtitle: AppLanguageManager.localized("profileSetup.location.subtitle")
            ) {
                ProfileSetupMapCityRow(
                    title: AppLanguageManager.localized("profileSetup.location.hometown"),
                    value: hometown,
                    actionTitle: AppLanguageManager.localized("profileSetup.location.searchHometown"),
                    onSearch: {
                        showingHometownSelector = true
                    }
                )

                ProfileSetupMapCityRow(
                    title: AppLanguageManager.localized("profileSetup.location.currentlyLiving"),
                    value: currentlyLiving,
                    actionTitle: AppLanguageManager.localized("profileSetup.location.searchCurrentCity"),
                    onSearch: {
                        showingCurrentlyLivingSelector = true
                    }
                )
            }

        case .background:
            ProfileSetupCard(
                icon: "checkmark.shield.fill",
                title: AppLanguageManager.localized("profileSetup.background.title"),
                subtitle: AppLanguageManager.localized("profileSetup.background.subtitle")
            ) {
                Toggle(isOn: $vm.isStudent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLanguageManager.localized("profileSetup.background.studentToggle"))
                            .font(.subheadline.weight(.semibold))
                        Text(AppLanguageManager.localized("profileSetup.background.workVerificationNotRequired"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: vm.isStudent) { _, isSelected in
                    guard isSelected else { return }
                    vm.isUnemployed = false
                    vm.jobTitle = ""
                    vm.companyName = ""
                }

                Toggle(isOn: $vm.isUnemployed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLanguageManager.localized("profileSetup.background.unemployedToggle"))
                            .font(.subheadline.weight(.semibold))
                        Text(AppLanguageManager.localized("profileSetup.background.workVerificationNotRequired"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: vm.isUnemployed) { _, isSelected in
                    guard isSelected else { return }
                    vm.isStudent = false
                    vm.jobTitle = ""
                    vm.companyName = ""
                }

                TextField(AppLanguageManager.localized("profileSetup.background.jobTitlePlaceholder"), text: $vm.jobTitle)
                    .profileSetupTextField()
                    .accessibilityLabel(AppLanguageManager.localized("profileSetup.background.jobTitlePlaceholder"))
                    .disabled(vm.hasNoWorkVerification)
                    .opacity(vm.hasNoWorkVerification ? 0.42 : 1)

                TextField(AppLanguageManager.localized("profileSetup.background.companyPlaceholder"), text: $vm.companyName)
                    .profileSetupTextField()
                    .accessibilityLabel(AppLanguageManager.localized("profileSetup.background.companyPlaceholder"))
                    .disabled(vm.hasNoWorkVerification)
                    .opacity(vm.hasNoWorkVerification ? 0.42 : 1)

                ProfileSetupStringPickerField(
                    title: AppLanguageManager.localized("profileSetup.background.educationLevel"),
                    selection: $vm.educationLevel,
                    options: ProfileSetupViewModel.educationLevels,
                    usesWheelPicker: false
                )

                TextField(AppLanguageManager.localized("profileSetup.background.schoolPlaceholder"), text: $vm.schoolName)
                    .profileSetupTextField()
                    .accessibilityLabel(AppLanguageManager.localized("profileSetup.background.schoolPlaceholder"))
            }

        case .datingIntentions:
            ProfileSetupCard(
                icon: "heart.fill",
                title: AppLanguageManager.localized("profileSetup.intentions.title"),
                subtitle: AppLanguageManager.localized("profileSetup.intentions.subtitle")
            ) {
                ProfileSetupEnumMenu(
                    title: AppLanguageManager.localized("profileSetup.intentions.lookingFor"),
                    selection: $vm.relationshipGoal,
                    options: RelationshipIntention.allCases.map { goal in
                        ProfileSetupPickerOption(value: goal, title: display(goal.rawValue))
                    }
                )

                ProfileSetupEnumMenu(
                    title: AppLanguageManager.localized("profileSetup.intentions.interestedIn"),
                    selection: $vm.genderInterest,
                    options: GenderInterest.allCases.map { option in
                        ProfileSetupPickerOption(value: option, title: display(option.rawValue))
                    }
                )
            }

        case .moreDetails:
            ProfileSetupCard(
                icon: "slider.horizontal.3",
                title: AppLanguageManager.localized("profileSetup.moreDetails.title"),
                subtitle: AppLanguageManager.localized("profileSetup.moreDetails.subtitle")
            ) {
                ProfileSetupBioEditor(text: $vm.bio)

                ProfileSetupOptionalEnumMenu(
                    title: AppLanguageManager.localized("profileSetup.moreDetails.maritalStatus"),
                    selection: $vm.maritalStatus,
                    options: MaritalStatus.allCases.map { status in
                        ProfileSetupPickerOption(value: status, title: status.title)
                    }
                )

                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.race"), selection: $vm.race, options: ProfileSetupViewModel.raceOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.religion"), selection: $vm.religion, options: ProfileSetupViewModel.religionOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.familyPlans"), selection: $vm.familyPlans, options: ProfileSetupViewModel.familyPlansOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.smoking"), selection: $vm.smoking, options: ProfileSetupViewModel.smokingOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.drinking"), selection: $vm.drinking, options: ProfileSetupViewModel.drinkingOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.exercise"), selection: $vm.exercise, options: ProfileSetupViewModel.exerciseOptions)
                ProfileSetupMultiSelectField(title: AppLanguageManager.localized("profileSetup.moreDetails.pets"), selectionText: $vm.pets, options: ProfileSetupViewModel.petOptions, maxSelection: 4)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.communicationStyle"), selection: $vm.communicationStyle, options: ProfileSetupViewModel.communicationStyleOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.loveLanguage"), selection: $vm.loveLanguage, options: ProfileSetupViewModel.loveLanguageOptions)
                ProfileSetupStringPickerField(title: AppLanguageManager.localized("profileSetup.moreDetails.mbti"), selection: $vm.mbti, options: ProfileSetupViewModel.mbtiOptions)
                ProfileSetupMultiSelectField(title: AppLanguageManager.localized("profileSetup.moreDetails.languages"), selectionText: $vm.languages, options: ProfileSetupViewModel.languageOptions, maxSelection: 6)
            }
        }

        if let error = vm.errorMessage {
            Text(error)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(error)
        }
    }

    private func goBack() {
        guard let previousStep = step.previous else { return }
        HapticManager.light()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            step = previousStep
        }
    }

    private func goNext() async {
        vm.errorMessage = nil

        guard validateCurrentStep() else {
            HapticManager.warning()
            return
        }

        if let nextStep = step.next {
            HapticManager.light()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                step = nextStep
            }
            return
        }

        await saveProfile()
    }

    private func validateCurrentStep() -> Bool {
        switch step {
        case .name:
            let name = vm.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                vm.errorMessage = AppLanguageManager.localized("profileSetup.error.fullNameRequired")
                return false
            }

            guard !vm.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                vm.errorMessage = AppLanguageManager.localized("profileSetup.error.displayNameRequired")
                return false
            }
        case .photos:
            guard !photos.isEmpty else {
                vm.errorMessage = AppLanguageManager.localized("profileSetup.error.photoRequired")
                return false
            }
        case .location:
            guard !currentlyLiving.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                vm.errorMessage = AppLanguageManager.localized("profileSetup.error.currentCityRequired")
                return false
            }
        case .background:
            if !vm.hasNoWorkVerification {
                guard !vm.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    vm.errorMessage = AppLanguageManager.localized("profileSetup.error.jobTitleRequired")
                    return false
                }

                guard !vm.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    vm.errorMessage = AppLanguageManager.localized("profileSetup.error.companyRequired")
                    return false
                }
            }

            guard !vm.schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                vm.errorMessage = AppLanguageManager.localized("profileSetup.error.schoolRequired")
                return false
            }
        default:
            break
        }

        return true
    }

    private func saveProfile() async {
        guard let userId = session.currentUserId else { return }

        vm.hometown = hometown
        vm.currentlyLiving = currentlyLiving
        vm.city = currentlyLiving

        let saved = await vm.save(userId: userId, coordinate: nil)
        if saved {
            await session.loadProfile()
            onCompleted?()
        }
    }

    private func hydrateFromCurrentProfileIfNeeded() {
        guard !hasHydratedProfile, let profile = session.currentProfile else { return }

        vm.fullName = profile.fullName ?? ""
        vm.displayName = profile.displayName ?? ""
        vm.gender = profile.gender ?? .male
        vm.maritalStatus = profile.maritalStatus
        vm.race = profile.race ?? ""
        vm.religion = profile.religion ?? ""
        vm.city = profile.city ?? ""
        vm.hometown = profile.hometown ?? ""
        vm.currentlyLiving = profile.currentlyLiving ?? profile.city ?? ""
        let jobTitle = profile.jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let companyName = profile.companyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        vm.isStudent = jobTitle.localizedCaseInsensitiveCompare("Student") == .orderedSame
        vm.isUnemployed = jobTitle.localizedCaseInsensitiveCompare("Unemployed") == .orderedSame
        vm.jobTitle = vm.hasNoWorkVerification ? "" : jobTitle
        vm.companyName = vm.hasNoWorkVerification ? "" : companyName
        vm.educationLevel = profile.educationLevel ?? "Degree"
        vm.schoolName = profile.schoolName ?? ""
        vm.heightCm = profile.heightCm ?? 170
        vm.relationshipGoal = profile.relationshipGoal ?? .serious_relationship
        vm.genderInterest = profile.genderInterest ?? .opposite_gender
        vm.smoking = profile.smoking ?? ""
        vm.drinking = profile.drinking ?? ""
        vm.exercise = profile.exercise ?? ""
        vm.bio = profile.bio ?? ""
        vm.pets = profile.pets ?? ""
        vm.communicationStyle = profile.communicationStyle ?? ""
        vm.loveLanguage = profile.loveLanguage ?? ""
        vm.mbti = profile.mbti ?? ""
        vm.languages = profile.languages ?? ""
        vm.familyPlans = profile.familyPlans ?? ""

        if let dateOfBirth = profile.dateOfBirth,
           let parsedDate = Self.profileDateFormatter.date(from: dateOfBirth) {
            vm.dateOfBirth = parsedDate
        }

        hometown = vm.hometown
        currentlyLiving = vm.currentlyLiving
        hasHydratedProfile = true
    }

    private func loadPhotos() async {
        guard let userId = session.currentUserId else { return }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        do {
            photos = try await ProfilePhotoService.shared.fetchPhotos(userId: userId)
                .sorted { $0.displayOrder < $1.displayOrder }
        } catch {
            photos = []
        }
    }

    private func handleUploadedPhoto(_ uploadedPhoto: ProfilePhoto) async {
        photos.removeAll { $0.id == uploadedPhoto.id || $0.displayOrder == uploadedPhoto.displayOrder }
        photos.append(uploadedPhoto)
        photos.sort { $0.displayOrder < $1.displayOrder }

        if uploadedPhoto.displayOrder == 0 {
            await session.loadProfile()
        }
    }

    private func delete(_ photo: ProfilePhoto) async {
        do {
            try await ProfilePhotoService.shared.deletePhoto(photo: photo)
            photos.removeAll { $0.id == photo.id }
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func display(_ value: String) -> String {
        LocalizedProfileDisplay.option(value)
    }

    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum ProfileSetupStep: Int, CaseIterable {
    case name
    case basics
    case photos
    case location
    case background
    case datingIntentions
    case moreDetails

    var title: String {
        switch self {
        case .name:
            return AppLanguageManager.localized("profileSetup.step.name")
        case .basics:
            return AppLanguageManager.localized("profileSetup.step.basics")
        case .photos:
            return AppLanguageManager.localized("profileSetup.step.photos")
        case .location:
            return AppLanguageManager.localized("profileSetup.step.location")
        case .background:
            return AppLanguageManager.localized("profileSetup.step.background")
        case .datingIntentions:
            return AppLanguageManager.localized("profileSetup.step.intentions")
        case .moreDetails:
            return AppLanguageManager.localized("profileSetup.step.details")
        }
    }

    var next: ProfileSetupStep? {
        ProfileSetupStep(rawValue: rawValue + 1)
    }

    var previous: ProfileSetupStep? {
        ProfileSetupStep(rawValue: rawValue - 1)
    }

    var progressText: String {
        String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.progress.format"), rawValue + 1, Self.allCases.count)
    }

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}

private struct ProfileSetupProgressHeader: View {
    let step: ProfileSetupStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(step.title)
                    .font(.title2.weight(.bold))

                Spacer()

                Text(step.progressText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }

            ProgressView(value: step.progress)
                .tint(.pink)
                .accessibilityLabel(step.title)
                .accessibilityValue(step.progressText)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }
}

private struct ProfileSetupCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.pink, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemGroupedBackground).opacity(0.36)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.045), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileSetupFooter: View {
    let step: ProfileSetupStep
    let isSaving: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguageManager.localized("common_back"))
            .disabled(step.previous == nil || isSaving)
            .opacity(step.previous == nil ? 0.35 : 1)

            Button {
                onNext()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .accessibilityHidden(true)
                    } else {
                        Text(step.next == nil ? AppLanguageManager.localized("profileSetup.footer.saveContinue") : AppLanguageManager.localized("common_continue"))
                        Image(systemName: step.next == nil ? "checkmark" : "chevron.right")
                            .accessibilityHidden(true)
                    }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.pink, in: Capsule())
                .shadow(color: Color.pink.opacity(0.22), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.next == nil ? AppLanguageManager.localized("profileSetup.footer.saveContinue") : AppLanguageManager.localized("common_continue"))
            .disabled(isSaving)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .background(.regularMaterial)
    }
}

private struct ProfileSetupHint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSetupPhotoGrid: View {
    let photos: [ProfilePhoto]
    let userId: UUID?
    let isLoading: Bool
    let onUploaded: (ProfilePhoto) async -> Void
    let onDelete: (ProfilePhoto) -> Void

    private let maxPhotos = 6
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var orderedPhotos: [ProfilePhoto] {
        photos.sorted { lhs, rhs in
            if lhs.displayOrder == rhs.displayOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.displayOrder < rhs.displayOrder
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.photos.countFormat"), orderedPhotos.count, maxPhotos))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.pink)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<maxPhotos, id: \.self) { index in
                    if index < orderedPhotos.count {
                        ProfileSetupPhotoCell(
                            photo: orderedPhotos[index],
                            slotNumber: index + 1,
                            isPrimary: index == 0,
                            onDelete: {
                                onDelete(orderedPhotos[index])
                            }
                        )
                    } else {
                        ProfileSetupEmptyPhotoCell(
                            slotNumber: index + 1,
                            userId: userId,
                            displayOrder: index,
                            maxSelectionCount: maxPhotos - index,
                            onUploaded: onUploaded
                        )
                    }
                }
            }
        }
    }
}

private struct ProfileSetupPhotoCell: View {
    let photo: ProfilePhoto
    let slotNumber: Int
    let isPrimary: Bool
    let onDelete: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(isPrimary ? AppLanguageManager.localized("profileSetup.photos.primary") : String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.photos.slotFormat"), slotNumber))
                .font(.caption.weight(.bold))
                .foregroundStyle(isPrimary ? .pink : .secondary)

            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.secondary.opacity(0.14)
                                .overlay {
                                    if isLoading {
                                        ProgressView()
                                            .accessibilityHidden(true)
                                    } else {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLanguageManager.localized("editProfile.photos.deletePhoto"))
                    .padding(7)
                }
            }
            .aspectRatio(0.76, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .task(id: photo.photoPath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        if let cachedImage = ProfilePhotoService.shared.cachedImage(for: photo.photoPath) {
            image = cachedImage
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }
        image = try? await ProfilePhotoService.shared.image(for: photo.photoPath)
    }
}

private struct ProfileSetupEmptyPhotoCell: View {
    let slotNumber: Int
    let userId: UUID?
    let displayOrder: Int
    let maxSelectionCount: Int
    let onUploaded: (ProfilePhoto) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(slotNumber == 1 ? AppLanguageManager.localized("profileSetup.photos.primary") : String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.photos.slotFormat"), slotNumber))
                .font(.caption.weight(.bold))
                .foregroundStyle(slotNumber == 1 ? .pink : .secondary)

            if let userId {
                PhotoUploadPicker(
                    userId: userId,
                    displayOrder: displayOrder,
                    slotNumber: slotNumber,
                    maxSelectionCount: maxSelectionCount,
                    onUploaded: onUploaded
                )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(0.76, contentMode: .fit)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ProfileSetupPickerOption<Value: Hashable>: Hashable {
    let value: Value
    let title: String
}

private struct ProfileSetupEnumMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [ProfileSetupPickerOption<Value>]
    var usesWheelPicker = false

    @State private var isShowingSelector = false

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("common_not_added")
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
                ProfileSetupSelectorLabel(value: selectedTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selectedTitle)
            .sheet(isPresented: $isShowingSelector) {
                ProfileSetupOptionSheet(
                    title: title,
                    selection: $selection,
                    options: options,
                    usesWheelPicker: usesWheelPicker
                )
                .presentationDetents(usesWheelPicker ? [.height(360)] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .profileSetupFieldContainer()
    }
}

private struct ProfileSetupOptionalEnumMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value?
    let options: [ProfileSetupPickerOption<Value>]

    @State private var isShowingSelector = false

    private var selectedTitle: String {
        guard let selection else { return AppLanguageManager.localized("common_not_added") }
        return options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("common_not_added")
    }

    private var sheetSelection: Binding<Value?> {
        Binding(
            get: { selection },
            set: { selection = $0 }
        )
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
                ProfileSetupSelectorLabel(value: selectedTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selectedTitle)
            .sheet(isPresented: $isShowingSelector) {
                ProfileSetupOptionalOptionSheet(
                    title: title,
                    selection: sheetSelection,
                    options: options
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .profileSetupFieldContainer()
    }
}

private struct ProfileSetupStringPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var usesWheelPicker = false

    var body: some View {
        ProfileSetupEnumMenu(
            title: title,
            selection: $selection,
            options: options.map { option in
                ProfileSetupPickerOption(value: option, title: option.isEmpty ? AppLanguageManager.localized("common_not_added") : localizedProfileSetupOption(option))
            },
            usesWheelPicker: usesWheelPicker
        )
    }
}

private struct ProfileSetupOptionSheet<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [ProfileSetupPickerOption<Value>]
    let usesWheelPicker: Bool

    @Environment(\.dismiss) private var dismiss

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("common_not_added")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProfileSetupSheetHeader(title: title, selectedTitle: selectedTitle)

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
                        Text(AppLanguageManager.localized("common_done"))
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.pink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLanguageManager.localized("common_done"))
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
                                    ProfileSetupOptionSheetRow(
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
                    Button(AppLanguageManager.localized("common_close")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel(AppLanguageManager.localized("common_close"))
                }
            }
        }
    }
}

private struct ProfileSetupOptionalOptionSheet<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value?
    let options: [ProfileSetupPickerOption<Value>]

    @Environment(\.dismiss) private var dismiss

    private var selectedTitle: String {
        guard let selection else { return AppLanguageManager.localized("common_not_added") }
        return options.first(where: { $0.value == selection })?.title ?? AppLanguageManager.localized("common_not_added")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProfileSetupSheetHeader(title: title, selectedTitle: selectedTitle)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        Button {
                            HapticManager.light()
                            selection = nil
                            dismiss()
                        } label: {
                            ProfileSetupOptionSheetRow(
                                title: AppLanguageManager.localized("common_not_added"),
                                isSelected: selection == nil
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(options, id: \.self) { option in
                            Button {
                                HapticManager.light()
                                selection = option.value
                                dismiss()
                            } label: {
                                ProfileSetupOptionSheetRow(
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
            .padding(.top, 14)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguageManager.localized("common_close")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel(AppLanguageManager.localized("common_close"))
                }
            }
        }
    }
}

private struct ProfileSetupSheetHeader: View {
    let title: String
    let selectedTitle: String

    var body: some View {
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
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSetupOptionSheetRow: View {
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
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.pink.opacity(0.24) : Color.black.opacity(0.04), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.07 : 0.035), radius: isSelected ? 10 : 6, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSelected ? AppLanguageManager.localized("filters_option_selected") : AppLanguageManager.localized("filters_option_not_selected"))
    }
}

private struct ProfileSetupSelectorLabel: View {
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(value == AppLanguageManager.localized("common_not_added") ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ProfileSetupMultiSelectField: View {
    let title: String
    @Binding var selectionText: String
    let options: [String]
    let maxSelection: Int

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

                Text(String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.multiselect.countFormat"), selectedValues.count, maxSelection))
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
                    ProfileSetupChip(
                        title: localizedProfileSetupOption(option),
                        isSelected: selectedValues.contains(option)
                    ) {
                        toggle(option)
                    }
                }
            }
        }
        .profileSetupFieldContainer()
    }

    private func toggle(_ option: String) {
        message = nil
        var values = selectedValues
        if values.contains(option) {
            values.removeAll { $0 == option }
        } else {
            guard values.count < maxSelection else {
                message = String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.multiselect.limitFormat"), maxSelection)
                return
            }
            values.append(option)
        }
        selectionText = values.joined(separator: ", ")
    }
}
private func localizedProfileSetupOption(_ value: String) -> String {
    LocalizedProfileDisplay.option(value)
}

private func legacyLocalizedProfileSetupOption(_ value: String) -> String {
    switch value {
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

private struct ProfileSetupBioEditor: View {
    @Binding var text: String
    private let maxLength = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLanguageManager.localized("profileSetup.bio.title"))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(String.localizedStringWithFormat(AppLanguageManager.localized("profileSetup.bio.countFormat"), text.count, maxLength))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(text.count > maxLength ? .red : .secondary)
            }

            TextField(
                AppLanguageManager.localized("profileSetup.bio.placeholder"),
                text: $text,
                axis: .vertical
            )
            .lineLimit(4...7)
            .font(.body)
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(AppLanguageManager.localized("profileSetup.bio.title"))
            .onChange(of: text) { _, newValue in
                if newValue.count > maxLength {
                    text = String(newValue.prefix(maxLength))
                }
            }

            Text(AppLanguageManager.localized("profileSetup.bio.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .profileSetupFieldContainer()
    }
}

private struct ProfileSetupChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.pink : Color(.systemBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.black.opacity(0.05), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? AppLanguageManager.localized("filters_option_selected") : AppLanguageManager.localized("filters_option_not_selected"))
    }
}

private struct ProfileSetupMapCityRow: View {
    let title: String
    let value: String
    let actionTitle: String
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.isEmpty ? AppLanguageManager.localized("common_not_added") : value)
                    .font(.subheadline)
                    .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                onSearch()
            } label: {
                Label(actionTitle, systemImage: "map")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .padding(.vertical, 11)
                    .background(Color.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionTitle)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private extension View {
    func profileSetupTextField() -> some View {
        self
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func profileSetupFieldContainer() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.035), lineWidth: 1)
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
