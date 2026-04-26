import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionViewModel

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.currentProfile {
                    Section("Profile") {
                        Text(profile.fullName ?? "No name")
                        Text(profile.latitude == nil || profile.longitude == nil ? "No location" : "Location added")
                        Text(profile.verificationStatus.rawValue.capitalized)
                    }
                }

                Button("Refresh") {
                    Task { await session.loadProfile() }
                }

                Button("Sign Out") {
                    Task { await session.signOut() }
                }
                .foregroundStyle(.red)
            }
            .navigationTitle("Me")
        }
    }
}
