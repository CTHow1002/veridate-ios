import CoreLocation
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var locationManager = LocationManager()
    @State private var isUpdatingLocation = false
    @State private var readableLocation: String?

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.currentProfile {
                    Section("Profile") {
                        Text(profile.fullName ?? "No name")
                        Text(locationText(for: profile))
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
            .task(id: locationKey) {
                await loadReadableLocation()
            }
            .onReceive(locationManager.$coordinate.compactMap { $0 }) { coordinate in
                Task {
                    isUpdatingLocation = true
                    _ = await session.updateProfileLocation(coordinate)
                    isUpdatingLocation = false
                }
            }
        }
    }

    private var locationKey: String {
        guard let latitude = session.currentProfile?.latitude,
              let longitude = session.currentProfile?.longitude else {
            return "missing-location"
        }

        return "\(latitude),\(longitude)"
    }

    private func locationText(for profile: Profile) -> String {
        guard let latitude = profile.latitude,
              let longitude = profile.longitude else {
            return "No location"
        }

        return readableLocation ?? String(format: "%.4f, %.4f", latitude, longitude)
    }

    private func loadReadableLocation() async {
        guard let latitude = session.currentProfile?.latitude,
              let longitude = session.currentProfile?.longitude else {
            readableLocation = nil
            return
        }

        let coordinateFallback = String(format: "%.4f, %.4f", latitude, longitude)
        readableLocation = coordinateFallback

        do {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
            let parts = [
                placemark?.locality,
                placemark?.administrativeArea,
                placemark?.country
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            if !parts.isEmpty {
                readableLocation = parts.joined(separator: ", ")
            }
        } catch {
            readableLocation = coordinateFallback
        }
    }
}
