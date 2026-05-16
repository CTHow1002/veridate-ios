import Foundation
import SwiftUI

struct PublicProfilePreviewContent: View {
    let profile: Profile
    let currentProfile: Profile?
    var locationTextOverride: String?
    var showsPreviewLabel = false

    @State private var photos: [PublicProfilePhotoItem] = []
    @State private var selectedPhotoIndex = 0
    @State private var prompts: [ProfilePrompt] = []
    @State private var interests: [String] = []
    @AppStorage(PrivacyPreferenceKey.showDistance) private var showDistance = true

    var body: some View {
        VStack(spacing: 18) {
            if showsPreviewLabel {
                Label(AppLanguageManager.localized("profile.preview.previewingPublicProfile"), systemImage: "eye.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PublicProfilePhotoCarousel(
                photos: photos,
                selectedIndex: $selectedPhotoIndex,
                profile: profile,
                locationText: headerLocationText
            )

            if let bio = cleaned(profile.bio) {
                PublicProfileSection(title: AppLanguageManager.localized("profile.preview.about")) {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let relationshipGoalText {
                PublicProfileLookingForCard(value: relationshipGoalText)
            }

            VerificationTrustCard(status: profile.verificationStatus)

            PublicProfileSection(title: AppLanguageManager.localized("profile.preview.datingBasics")) {
                VStack(spacing: 12) {
                    PublicProfileDetailRow(
                        systemImage: "person.fill",
                        title: AppLanguageManager.localized("profile.preview.gender"),
                        value: profile.gender.map { LocalizedProfileDisplay.gender($0) }
                    )

                    PublicProfileDetailRow(
                        systemImage: "person.2.fill",
                        title: AppLanguageManager.localized("profile.preview.maritalStatus"),
                        value: profile.maritalStatus.map { LocalizedProfileDisplay.maritalStatus($0) }
                    )

                    PublicProfileDetailRow(
                        systemImage: "person.text.rectangle.fill",
                        title: AppLanguageManager.localized("profile.preview.race"),
                        value: localizedOption(profile.race)
                    )

                    PublicProfileDetailRow(
                        systemImage: "sparkles",
                        title: AppLanguageManager.localized("profile.preview.religion"),
                        value: localizedOption(profile.religion)
                    )

                    PublicProfileDetailRow(
                        systemImage: "ruler.fill",
                        title: AppLanguageManager.localized("profile.preview.height"),
                        value: profile.heightCm.map { String.localizedStringWithFormat(AppLanguageManager.localized("profile_height_cm_format"), $0) }
                    )

                    PublicProfileDetailRow(
                        systemImage: "figure.2.and.child.holdinghands",
                        title: AppLanguageManager.localized("profile.preview.familyPlans"),
                        value: localizedOption(profile.familyPlans)
                    )
                }
            }

            PublicProfileSection(title: AppLanguageManager.localized("profile.preview.lifestylePersonality")) {
                VStack(spacing: 12) {
                    PublicProfileDetailRow(systemImage: "smoke.fill", title: AppLanguageManager.localized("profile.preview.smoking"), value: localizedOption(profile.smoking))
                    PublicProfileDetailRow(systemImage: "wineglass.fill", title: AppLanguageManager.localized("profile.preview.drinking"), value: localizedOption(profile.drinking))
                    PublicProfileDetailRow(systemImage: "figure.run", title: AppLanguageManager.localized("profile.preview.exercise"), value: localizedOption(profile.exercise))
                    PublicProfileDetailRow(systemImage: "pawprint.fill", title: AppLanguageManager.localized("profile.preview.pets"), value: localizedList(profile.pets))
                    PublicProfileDetailRow(systemImage: "bubble.left.and.bubble.right.fill", title: AppLanguageManager.localized("profile.preview.communication"), value: localizedList(profile.communicationStyle))
                    PublicProfileDetailRow(systemImage: "heart.text.square.fill", title: AppLanguageManager.localized("profile.preview.loveLanguage"), value: localizedOption(profile.loveLanguage))
                    PublicProfileDetailRow(systemImage: "moon.stars.fill", title: AppLanguageManager.localized("profile.preview.horoscope"), value: localizedOption(profile.horoscope))
                    PublicProfileDetailRow(systemImage: "brain.head.profile", title: AppLanguageManager.localized("profile.preview.mbti"), value: localizedMBTI(profile.mbti))
                    PublicProfileDetailRow(systemImage: "character.bubble.fill", title: AppLanguageManager.localized("profile.preview.languages"), value: LocalizedProfileDisplay.languageList(profile.languages))
                }
            }

            PublicProfileSection(title: AppLanguageManager.localized("profile.preview.background")) {
                VStack(spacing: 12) {
                    PublicProfileDetailRow(
                        systemImage: "briefcase.fill",
                        title: AppLanguageManager.localized("profile.preview.work"),
                        value: joinedText(localizedOption(profile.displayJobTitle), profile.displayCompanyName)
                    )

                    PublicProfileDetailRow(
                        systemImage: "graduationcap.fill",
                        title: AppLanguageManager.localized("profile.preview.education"),
                        value: joinedText(localizedOption(profile.educationLevel), profile.schoolName)
                    )

                    PublicProfileDetailRow(
                        systemImage: "house.fill",
                        title: AppLanguageManager.localized("profile.preview.hometown"),
                        value: profile.hometown
                    )

                    PublicProfileDetailRow(
                        systemImage: "mappin.and.ellipse",
                        title: AppLanguageManager.localized("profile.preview.currentlyLiving"),
                        value: joinedText(profile.currentlyLiving ?? profile.city, profile.country)
                    )

                    if showDistance {
                        PublicProfileDetailRow(
                            systemImage: "location.fill",
                            title: AppLanguageManager.localized("profile.preview.distanceFromYou"),
                            value: distanceText
                        )
                    }
                }
            }

            if !prompts.isEmpty {
                PublicProfileSection(title: AppLanguageManager.localized("profile.preview.prompts")) {
                    VStack(spacing: 12) {
                        ForEach(prompts) { prompt in
                            PublicProfilePromptCard(prompt: prompt)
                        }
                    }
                }
            }

            if !interests.isEmpty {
                PublicProfileSection(title: AppLanguageManager.localized("profile.preview.lifestyleInterests")) {
                    PublicProfileInterestChips(interests: interests)
                }
            }
        }
        .task(id: profile.id) {
            await loadPhotos()
            await loadPrompts()
            await loadInterests()
        }
    }

    private var headerLocationText: String {
        let location = cleaned(locationTextOverride)
            ?? joinedText(profile.currentlyLiving ?? profile.city, profile.country)

        if let location, let distanceText {
            return "\(location) • \(distanceText)"
        }

        if let location {
            return location
        }

        if let distanceText {
            return distanceText
        }

        return AppLanguageManager.localized("profile.preview.locationNotAdded")
    }

    private var relationshipGoalText: String? {
        profile.relationshipGoal.map { LocalizedProfileDisplay.relationshipGoal($0) }
    }

    private var distanceText: String? {
        guard showDistance else { return nil }
        guard currentProfile?.id != profile.id else { return nil }

        guard
            let currentLatitude = currentProfile?.latitude,
            let currentLongitude = currentProfile?.longitude,
            let profileLatitude = profile.latitude,
            let profileLongitude = profile.longitude
        else {
            return nil
        }

        let distance = haversineDistanceKm(
            fromLatitude: currentLatitude,
            fromLongitude: currentLongitude,
            toLatitude: profileLatitude,
            toLongitude: profileLongitude
        )

        if distance < 1 {
            return AppLanguageManager.localized("profile.preview.lessThanOneKmAway")
        }

        return String.localizedStringWithFormat(AppLanguageManager.localized("profile.preview.kmAwayFormat"), Int(distance.rounded()))
    }

    private func loadPhotos() async {
        do {
            let fetchedPhotos = try await ProfilePhotoService.shared.fetchPhotos(userId: profile.id)
            var loadedPhotos: [PublicProfilePhotoItem] = []

            for photo in fetchedPhotos {
                if let image = try? await ProfilePhotoService.shared.image(for: photo.photoPath) {
                    loadedPhotos.append(PublicProfilePhotoItem(id: photo.id.uuidString, image: image))
                }
            }

            if !loadedPhotos.isEmpty {
                photos = loadedPhotos
                selectedPhotoIndex = 0
                return
            }
        } catch {
            // Fall back to the primary profile photo below.
        }

        if let fallbackPhoto = await resolvePhoto(from: profile.profilePhotoURL) {
            photos = [fallbackPhoto]
        } else {
            photos = []
        }
        selectedPhotoIndex = 0
    }

    private func loadPrompts() async {
        do {
            prompts = try await ProfilePromptService.shared.loadProfilePrompts(userId: profile.id)
                .filter { cleaned($0.answer) != nil }
        } catch {
            prompts = []
        }
    }

    private func loadInterests() async {
        do {
            interests = try await ProfileInterestService.shared.loadProfileInterests(userId: profile.id)
        } catch {
            interests = []
        }
    }

    private func resolvePhoto(from path: String?) async -> PublicProfilePhotoItem? {
        guard let path = cleaned(path) else { return nil }

        if let directURL = URL(string: path), directURL.scheme?.hasPrefix("http") == true {
            guard let image = await loadImage(from: directURL) else { return nil }
            return PublicProfilePhotoItem(id: directURL.absoluteString, image: image)
        }

        guard let image = try? await ProfilePhotoService.shared.image(for: path) else { return nil }
        return PublicProfilePhotoItem(id: path, image: image)
    }

    private func loadImage(from url: URL) async -> UIImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func joinedText(_ first: String?, _ second: String?) -> String? {
        let values = [first, second]
            .compactMap { cleaned($0) }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedOption(_ value: String?) -> String? {
        guard let value = cleaned(value) else { return nil }
        return LocalizedProfileDisplay.option(value)
    }

    private func localizedList(_ value: String?) -> String? {
        LocalizedProfileDisplay.list(value)
    }

    private func localizedMBTI(_ value: String?) -> String? {
        guard let value = cleaned(value) else { return nil }
        let mbtiOptions: Set<String> = [
            "INTJ", "INTP", "ENTJ", "ENTP",
            "INFJ", "INFP", "ENFJ", "ENFP",
            "ISTJ", "ISFJ", "ESTJ", "ESFJ",
            "ISTP", "ISFP", "ESTP", "ESFP"
        ]

        return mbtiOptions.contains(value.uppercased()) ? value.uppercased() : LocalizedProfileDisplay.option(value)
    }

    private func haversineDistanceKm(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let latitudeDelta = degreesToRadians(toLatitude - fromLatitude)
        let longitudeDelta = degreesToRadians(toLongitude - fromLongitude)
        let fromLatitudeRadians = degreesToRadians(fromLatitude)
        let toLatitudeRadians = degreesToRadians(toLatitude)

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(fromLatitudeRadians) * cos(toLatitudeRadians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

private struct PublicProfilePhotoItem: Identifiable {
    let id: String
    let image: UIImage
}

private struct PublicProfilePhotoCarousel: View {
    let photos: [PublicProfilePhotoItem]
    @Binding var selectedIndex: Int

    let profile: Profile
    let locationText: String

    private var displayName: String {
        profile.publicName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? profile.publicName ?? AppLanguageManager.localized("profile.preview.noName")
            : AppLanguageManager.localized("profile.preview.noName")
    }

    private var ageText: String? {
        profile.displayAge.map { "\($0)" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if photos.isEmpty {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.pink.opacity(0.12))
                    .frame(height: 520)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.pink.opacity(0.5))
                            .accessibilityHidden(true)
                    }
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        PublicProfilePhotoPage(image: photo.image)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 520)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                if photos.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(0..<photos.count, id: \.self) { index in
                            Capsule()
                                .fill(index <= selectedIndex ? Color.white : Color.white.opacity(0.22))
                                .frame(height: 4)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(displayName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)

                        if let ageText {
                            Text(ageText)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }

                        if profile.verificationStatus == .verified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                                .accessibilityLabel(AppLanguageManager.localized("profile.verifiedBadge.accessibilityLabel"))
                        }
                    }

                    Label(locationText, systemImage: "location.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 22)
            .padding(.horizontal, 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct PublicProfilePhotoPage: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .background(Color(.secondarySystemFill))
        }
        .frame(height: 520)
        .clipped()
    }
}

private struct PublicProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

private struct PublicProfilePromptCard: View {
    let prompt: ProfilePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedProfileDisplay.option(prompt.prompt))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(prompt.answer)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PublicProfileInterestChips: View {
    let interests: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(interests, id: \.self) { interest in
                Text(LocalizedProfileDisplay.option(interest))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.pink.opacity(0.10), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PublicProfileLifestyleHighlights: View {
    let interests: [String]

    private var highlightedInterests: [String] {
        Array(interests.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguageManager.localized("profile.preview.lifestyleHighlights"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(highlightedInterests, id: \.self) { interest in
                    HStack(spacing: 10) {
                        Image(systemName: iconName(for: interest))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.pink)
                            .frame(width: 22, height: 22)

                        Text(displayTitle(for: interest))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func displayTitle(for interest: String) -> String {
        LocalizedProfileDisplay.option(interest)
    }

    private func iconName(for interest: String) -> String {
        let lowercased = interest.lowercased()

        if lowercased.contains("gym") || lowercased.contains("fitness") {
            return "figure.strengthtraining.traditional"
        }

        if lowercased.contains("travel") {
            return "airplane"
        }

        if lowercased.contains("coffee") {
            return "cup.and.saucer.fill"
        }

        if lowercased.contains("music") {
            return "music.note"
        }

        if lowercased.contains("food") || lowercased.contains("cafe") {
            return "fork.knife"
        }

        if lowercased.contains("movie") || lowercased.contains("film") {
            return "film.fill"
        }

        if lowercased.contains("book") {
            return "book.fill"
        }

        if lowercased.contains("gaming") {
            return "gamecontroller.fill"
        }

        return "sparkles"
    }
}

private struct PublicProfileDetailRow: View {
    let systemImage: String
    let title: String
    let value: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value?.isEmpty == false ? value ?? AppLanguageManager.localized("common_not_added") : AppLanguageManager.localized("common_not_added"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(value?.isEmpty == false ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PublicProfileLookingForCard: View {
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)

                Text(AppLanguageManager.localized("profile.preview.lookingFor"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(AppLanguageManager.localized("profile.preview.sharedIntentions"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .contain)
    }
}
