import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = DiscoveryViewModel()
    @State private var isShowingFilters = false

    var body: some View {
        NavigationStack {
            VStack {
                if let error = vm.errorMessage, vm.profiles.isEmpty {
                    ContentUnavailableView("No nearby profiles", systemImage: "location", description: Text(error))
                } else if vm.profiles.isEmpty {
                    ContentUnavailableView("No profiles yet", systemImage: "person.2", description: Text("Try a wider distance."))
                } else {
                    List(vm.profiles) { profile in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.fullName ?? "Verified User")
                                .font(.headline)

                            Text("\(profile.age ?? 0)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let bio = profile.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.body)
                            }

                            HStack {
                                Button("Pass") {
                                    Task {
                                        guard let userId = session.currentUserId else { return }
                                        await vm.pass(userId: userId, targetUserId: profile.id)
                                    }
                                }

                                Spacer()

                                Button("Like") {
                                    Task {
                                        guard let userId = session.currentUserId else { return }
                                        await vm.like(userId: userId, targetUserId: profile.id)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
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
            .task {
                guard let userId = session.currentUserId else { return }
                await vm.loadFilters(userId: userId)
                await vm.loadProfiles(userId: userId, currentProfile: session.currentProfile)
            }
        }
    }
}
