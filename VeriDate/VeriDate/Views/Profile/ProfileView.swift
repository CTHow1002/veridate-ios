import CoreLocation
import Combine
import Foundation
import MapKit
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

        guard #available(iOS 26.0, *) else {
            return
        }

        do {
            guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
                  let mapItem = try await request.mapItems.first else {
                return
            }

            if let cityWithContext = mapItem.addressRepresentations?.cityWithContext,
               let cityState = conciseCityState(from: cityWithContext) {
                readableLocation = cityState
            } else if let fullAddress = mapItem.address?.fullAddress,
                      let cityState = conciseCityState(from: fullAddress) {
                readableLocation = cityState
            } else if let name = mapItem.name, !name.isEmpty {
                readableLocation = name
            }
        } catch {
            readableLocation = coordinateFallback
        }
    }

    private func conciseCityState(from address: String) -> String? {
        var parts = address
            .replacingOccurrences(of: "\n", with: ",")
            .components(separatedBy: ",")
            .map { cleanAddressPart($0) }
            .filter { !$0.isEmpty }

        parts.removeAll { part in
            let lowercased = part.lowercased()
            return lowercased == "malaysia" || lowercased == "my"
        }

        guard parts.count >= 2 else {
            return parts.first
        }

        let city = parts[parts.count - 2]
        let state = parts[parts.count - 1]
        return "\(city), \(state)"
    }

    private func cleanAddressPart(_ part: String) -> String {
        part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^\d{4,6}\s*"#,
                with: "",
                options: .regularExpression
            )
    }
}
