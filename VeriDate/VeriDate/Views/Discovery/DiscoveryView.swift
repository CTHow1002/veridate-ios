import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = DiscoveryViewModel()
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var isShowingFilters = false
    @State private var reportProfile: Profile?
    @State private var blockProfile: Profile?
    @State private var noticeMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if session.currentProfile?.verificationStatus != .verified {
                    ContentUnavailableView(
                        "Verification Required",
                        systemImage: "checkmark.seal",
                        description: Text("Only verified users can discover profiles.")
                    )
                } else if vm.isLoading {
                    ProgressView("Loading profiles...")
                } else if let error = vm.errorMessage, vm.profiles.isEmpty {
                    ContentUnavailableView("Could Not Load Profiles", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let profile = vm.profiles.first {
                    ScrollView {
                        NavigationLink {
                            DiscoveryProfileDetailView(
                                profile: profile,
                                currentProfile: session.currentProfile
                            ) {
                                vm.removeProfile(id: profile.id)
                            }
                            .environmentObject(session)
                        } label: {
                            DiscoveryProfileCard(profile: profile, currentProfile: session.currentProfile)
                                .padding()
                        }
                        .buttonStyle(.plain)

                        actionBar(for: profile)
                            .padding(.horizontal)
                            .padding(.bottom)
                    }
                    .refreshable {
                        await load()
                    }
                } else {
                    ContentUnavailableView("No Profiles Yet", systemImage: "person.2", description: Text("Try updating your filters later."))
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                Button {
                    isShowingFilters = true
                } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                if let userId = session.currentUserId {
                    FiltersView(
                        vm: vm,
                        userId: userId,
                        currentProfile: session.currentProfile
                    ) {
                        isShowingFilters = false
                    }
                }
            }
            .sheet(item: $reportProfile) { profile in
                if let userId = session.currentUserId {
                    SafetyReportSheet(
                        reporterUserId: userId,
                        reportedUserId: profile.id,
                        matchId: nil,
                        reportedName: profile.fullName ?? "User"
                    )
                }
            }
            .alert("Block User?", isPresented: blockAlertBinding) {
                Button("Cancel", role: .cancel) {
                    blockProfile = nil
                }
                Button("Block", role: .destructive) {
                    Task {
                        await blockSelectedProfile()
                    }
                }
            } message: {
                Text("This user will be removed from Discover and hidden from your matches.")
            }
            .alert("Safety", isPresented: noticeBinding) {
                Button("OK") {
                    noticeMessage = nil
                    safetyVM.errorMessage = nil
                    safetyVM.successMessage = nil
                }
            } message: {
                Text(noticeMessage ?? "")
            }
            .task(id: session.currentUserId) {
                await load()
            }
        }
    }

    private func actionBar(for profile: Profile) -> some View {
        HStack(spacing: 16) {
            Menu {
                Button(role: .destructive) {
                    reportProfile = profile
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }

                Button(role: .destructive) {
                    blockProfile = profile
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    guard let userId = session.currentUserId else { return }
                    await vm.pass(userId: userId, targetUserId: profile.id)
                }
            } label: {
                Label("Pass", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.actingProfileIds.contains(profile.id))

            Button {
                Task {
                    guard let userId = session.currentUserId else { return }
                    await vm.like(userId: userId, targetUserId: profile.id)
                }
            } label: {
                Label("Like", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.actingProfileIds.contains(profile.id))
        }
    }

    private func load() async {
        guard let userId = session.currentUserId else { return }
        await vm.loadFilters(userId: userId)
        await vm.loadProfiles(userId: userId, currentProfile: session.currentProfile)
    }

    private var blockAlertBinding: Binding<Bool> {
        Binding(
            get: { blockProfile != nil },
            set: { isPresented in
                if !isPresented {
                    blockProfile = nil
                }
            }
        )
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { noticeMessage != nil },
            set: { isPresented in
                if !isPresented {
                    noticeMessage = nil
                }
            }
        )
    }

    private func blockSelectedProfile() async {
        guard let userId = session.currentUserId, let profile = blockProfile else { return }
        let didBlock = await safetyVM.blockUser(
            blockerUserId: userId,
            blockedUserId: profile.id,
            matchId: nil
        )

        if didBlock {
            vm.removeProfile(id: profile.id)
            noticeMessage = safetyVM.successMessage
        } else {
            noticeMessage = safetyVM.errorMessage
        }

        blockProfile = nil
    }
}

private struct DiscoveryProfileCard: View {
    let profile: Profile
    let currentProfile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfilePhotoView(urlString: profile.profilePhotoURL)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(profile.fullName ?? "Verified User")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(ageText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                infoRows
            }
            .padding([.horizontal, .bottom], 16)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(genderText, systemImage: "person")

            Label(distanceText, systemImage: "location")

            Label(relationshipGoalText, systemImage: "heart.text.square")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var ageText: String {
        guard let age = profile.age else {
            return "Age not added"
        }

        return "\(age)"
    }

    private var genderText: String {
        guard let gender = profile.gender else {
            return "Gender not added"
        }

        return display(gender.rawValue)
    }

    private var relationshipGoalText: String {
        guard let goal = profile.relationshipGoal else {
            return "Relationship goal not added"
        }

        return display(goal.rawValue)
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var distanceText: String {
        guard
            let currentLatitude = currentProfile?.latitude,
            let currentLongitude = currentProfile?.longitude,
            let profileLatitude = profile.latitude,
            let profileLongitude = profile.longitude
        else {
            return "Distance unavailable"
        }

        let distance = haversineDistanceKm(
            fromLatitude: currentLatitude,
            fromLongitude: currentLongitude,
            toLatitude: profileLatitude,
            toLongitude: profileLongitude
        )

        if distance < 1 {
            return "Less than 1 km away"
        }

        return "\(Int(distance.rounded())) km away"
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

private struct ProfilePhotoView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        photoPlaceholder
                            .overlay { ProgressView() }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        photoPlaceholder
                    @unknown default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var photoPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "person.crop.square")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiscoveryProfileDetailView: View {
    @EnvironmentObject var session: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var safetyVM = SafetyViewModel()
    @State private var isShowingReport = false
    @State private var isShowingBlockAlert = false
    @State private var noticeMessage: String?

    let profile: Profile
    let currentProfile: Profile?
    let onBlocked: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfilePhotoView(urlString: profile.profilePhotoURL)

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.fullName ?? "Verified User")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text(summaryText)
                        .foregroundStyle(.secondary)
                }

                details

                VStack(spacing: 10) {
                    Button(role: .destructive) {
                        isShowingReport = true
                    } label: {
                        Label("Report User", systemImage: "exclamationmark.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        isShowingBlockAlert = true
                    } label: {
                        Label("Block User", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(safetyVM.isSubmitting)
                }
            }
            .padding()
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingReport) {
            if let userId = session.currentUserId {
                SafetyReportSheet(
                    reporterUserId: userId,
                    reportedUserId: profile.id,
                    matchId: nil,
                    reportedName: profile.fullName ?? "User"
                )
            }
        }
        .alert("Block User?", isPresented: $isShowingBlockAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                Task {
                    await blockUser()
                }
            }
        } message: {
            Text("This user will be removed from Discover and hidden from your matches.")
        }
        .alert("Safety", isPresented: noticeBinding) {
            Button("OK") {
                noticeMessage = nil
                if safetyVM.successMessage != nil {
                    dismiss()
                }
            }
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(title: "Location", value: joinParts([profile.city, profile.country]))
            DetailRow(title: "Work", value: joinParts([profile.jobTitle, profile.companyName]))
            DetailRow(title: "Education", value: joinParts([profile.educationLevel, profile.schoolName]))
            DetailRow(title: "Height", value: profile.heightCm.map { "\($0) cm" } ?? "Not provided")
            DetailRow(title: "Relationship Goal", value: relationshipGoalText)
            DetailRow(title: "Bio", value: profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Not provided")
        }
    }

    private var summaryText: String {
        joinParts([ageText, genderText, distanceText])
    }

    private var ageText: String {
        profile.age.map { "\($0)" } ?? "Age not added"
    }

    private var genderText: String {
        profile.gender.map { display($0.rawValue) } ?? "Gender not added"
    }

    private var relationshipGoalText: String {
        profile.relationshipGoal.map { display($0.rawValue) } ?? "Not provided"
    }

    private var distanceText: String {
        guard
            let currentLatitude = currentProfile?.latitude,
            let currentLongitude = currentProfile?.longitude,
            let profileLatitude = profile.latitude,
            let profileLongitude = profile.longitude
        else {
            return "Distance unavailable"
        }

        let distance = haversineDistanceKm(
            fromLatitude: currentLatitude,
            fromLongitude: currentLongitude,
            toLatitude: profileLatitude,
            toLongitude: profileLongitude
        )

        if distance < 1 {
            return "Less than 1 km away"
        }

        return "\(Int(distance.rounded())) km away"
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { noticeMessage != nil },
            set: { isPresented in
                if !isPresented {
                    noticeMessage = nil
                    safetyVM.errorMessage = nil
                    safetyVM.successMessage = nil
                }
            }
        )
    }

    private func blockUser() async {
        guard let userId = session.currentUserId else { return }
        let didBlock = await safetyVM.blockUser(
            blockerUserId: userId,
            blockedUserId: profile.id,
            matchId: nil
        )

        if didBlock {
            onBlocked()
            noticeMessage = safetyVM.successMessage
        } else {
            noticeMessage = safetyVM.errorMessage
        }
    }

    private func joinParts(_ parts: [String?]) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
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

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
