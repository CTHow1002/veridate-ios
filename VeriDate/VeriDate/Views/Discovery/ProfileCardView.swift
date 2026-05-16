import SwiftUI

struct ProfileCardView: View {
    let profile: Profile
    @EnvironmentObject private var session: SessionViewModel

    @State private var photoImage: UIImage?
    @State private var prompts: [ProfilePrompt] = []
    @State private var interests: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photoImage {
                Image(uiImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 280)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                placeholderImage
            }

            Text(profile.publicName ?? AppLanguageManager.localized("common_verified_user"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(primaryInfoText)
                .foregroundStyle(.secondary)

            if let currentlyLivingText {
                Text(currentlyLivingText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let hometownText {
                Text(hometownText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let distanceText {
                Text(distanceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let job = profile.jobTitle, !job.isEmpty {
                Text(LocalizedProfileDisplay.option(job))
                    .font(.subheadline)
            }

            if let education = profile.educationLevel, !education.isEmpty {
                Text(LocalizedProfileDisplay.option(education))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
            }

            ProfileInterestDisplayView(interests: interests)
            ProfilePromptDisplayView(prompts: prompts)
        }
        .task {
            await loadPhoto()
            await loadInterests()
            await loadPrompts()
        }
    }

    private var primaryInfoText: String {
        let agePart: String
        if let age = profile.displayAge {
            agePart = "\(age)"
        } else {
            agePart = AppLanguageManager.localized("profile_age_not_added")
        }

        let genderPart = profile.gender.map { LocalizedProfileDisplay.gender($0) } ?? AppLanguageManager.localized("profile_gender_not_added")
        return String.localizedStringWithFormat(AppLanguageManager.localized("profile_card_primary_info_format"), agePart, genderPart)
    }


    private var currentlyLivingText: String? {
        let city = profile.currentlyLiving ?? profile.city
        guard let city, !city.isEmpty else { return nil }
        return String.localizedStringWithFormat(AppLanguageManager.localized("profile.card.currentlyLivingFormat"), city)
    }

    private var hometownText: String? {
        guard let hometown = profile.hometown, !hometown.isEmpty else { return nil }
        return String.localizedStringWithFormat(AppLanguageManager.localized("profile.card.fromFormat"), hometown)
    }


    private var distanceText: String? {
        guard let myLatitude = session.currentProfile?.latitude,
              let myLongitude = session.currentProfile?.longitude,
              let theirLatitude = profile.latitude,
              let theirLongitude = profile.longitude else {
            return nil
        }

        let distance = distanceInKilometers(
            fromLatitude: myLatitude,
            fromLongitude: myLongitude,
            toLatitude: theirLatitude,
            toLongitude: theirLongitude
        )

        if distance < 1 {
            return AppLanguageManager.localized("profile_distance_less_than_1km")
        } else {
            return String.localizedStringWithFormat(AppLanguageManager.localized("profile_distance_km_away_format"), Int(distance.rounded()))
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.gray.opacity(0.2))
            .frame(height: 280)
            .overlay {
                Image(systemName: "person.crop.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(AppLanguageManager.localized("profile_photo_placeholder_accessibility_label"))
    }

    private func loadPhoto() async {
        guard let path = profile.profilePhotoURL, !path.isEmpty else { return }

        do {
            if let directURL = URL(string: path), directURL.scheme?.hasPrefix("http") == true {
                let (data, _) = try await URLSession.shared.data(from: directURL)
                photoImage = UIImage(data: data)
            } else {
                photoImage = try await ProfilePhotoService.shared.image(for: path)
            }
        } catch {
            print("Failed to load signed photo URL:", error.localizedDescription)
        }
    }

    private func loadPrompts() async {
        do {
            prompts = try await ProfilePromptService.shared.loadProfilePrompts(userId: profile.id)
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

    private func distanceInKilometers(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = degreesToRadians(toLatitude - fromLatitude)
        let dLon = degreesToRadians(toLongitude - fromLongitude)

        let lat1 = degreesToRadians(fromLatitude)
        let lat2 = degreesToRadians(toLatitude)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusKm * c
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
