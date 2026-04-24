import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = DiscoveryViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                if vm.profiles.isEmpty {
                    ContentUnavailableView("No profiles yet", systemImage: "person.2", description: Text("Try adjusting filters later."))
                } else {
                    List(vm.profiles) { profile in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.fullName ?? "Verified User")
                                .font(.headline)

                            Text("\(profile.age ?? 0) • \(profile.city ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(profile.bio ?? "")
                                .font(.body)

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
            .task {
                guard let userId = session.currentUserId else { return }
                await vm.loadProfiles(userId: userId)
            }
        }
    }
}
