import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = DiscoveryViewModel()
    @State private var isShowingFilters = false

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
                        DiscoveryProfileCard(profile: profile)
                            .padding()

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
            .task(id: session.currentUserId) {
                await load()
            }
        }
    }

    private func actionBar(for profile: Profile) -> some View {
        HStack(spacing: 16) {
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
}

private struct DiscoveryProfileCard: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfilePhotoView(urlString: profile.profilePhotoURL)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(profile.fullName ?? "Verified User")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let age = profile.age {
                        Text("\(age)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                infoRows

                if let bio = clean(profile.bio) {
                    Text(bio)
                        .font(.body)
                        .padding(.top, 4)
                }
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
            Label(clean(profile.city) ?? "City not added", systemImage: "mappin.and.ellipse")

            if let job = clean(profile.jobTitle) {
                Label(job, systemImage: "briefcase")
            }

            if let education = clean(profile.educationLevel) {
                Label(education, systemImage: "graduationcap")
            }

            if let goal = profile.relationshipGoal {
                Label(display(goal.rawValue), systemImage: "heart.text.square")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
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
