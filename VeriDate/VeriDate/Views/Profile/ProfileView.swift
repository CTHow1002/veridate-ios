import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var isUpdatingLocation = false

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

                Section("Location") {
                    Label(locationManager.statusMessage, systemImage: locationManager.hasLocation ? "location.fill" : "location")

                    Button {
                        locationManager.requestLocation()
                    } label: {
                        if isUpdatingLocation {
                            ProgressView()
                        } else {
                            Text(session.currentProfile?.latitude == nil || session.currentProfile?.longitude == nil ? "Add Current Location" : "Update Current Location")
                        }
                    }
                    .disabled(isUpdatingLocation)

                    if let error = locationManager.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
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
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                Task {
                    isUpdatingLocation = true
                    _ = await session.updateProfileLocation(coordinate)
                    isUpdatingLocation = false
                }
            }
        }
    }
}
