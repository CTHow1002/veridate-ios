import Combine
import CoreLocation
import Foundation
import MapKit

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var cityState: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var hasLocation: Bool {
        coordinate != nil
    }

    var statusMessage: String {
        if coordinate != nil {
            return AppLanguageManager.localized("location.status.ready")
        }

        switch authorizationStatus {
        case .notDetermined:
            return AppLanguageManager.localized("location.status.permissionNeeded")
        case .restricted, .denied:
            return AppLanguageManager.localized("location.status.off")
        case .authorizedAlways, .authorizedWhenInUse:
            return AppLanguageManager.localized("location.status.finding")
        @unknown default:
            return AppLanguageManager.localized("location.status.unavailable")
        }
    }

    func requestLocation() {
        errorMessage = nil
        cityState = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            authorizationStatus = manager.authorizationStatus
            errorMessage = AppLanguageManager.localized("location.error.allowAccessInSettings")
        @unknown default:
            authorizationStatus = manager.authorizationStatus
            errorMessage = AppLanguageManager.localized("location.error.checkPermission")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        coordinate = location.coordinate
        errorMessage = nil

        Task {
            let resolvedCityState = await Self.cityState(for: location)

            await MainActor.run {
                self.cityState = resolvedCityState
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = String.localizedStringWithFormat(
            AppLanguageManager.localized("location.error.getLocationFormat"),
            error.localizedDescription
        )
    }

    @available(iOS 26.0, *)
    static func cityState(for location: CLLocation) async -> String? {
        do {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItem = try await request.mapItems.first else {
                return nil
            }

            if let cityWithContext = mapItem.addressRepresentations?.cityWithContext,
               let cityState = conciseCityState(from: cityWithContext) {
                return cityState
            }

            if let fullAddress = mapItem.address?.fullAddress,
               let cityState = conciseCityState(from: fullAddress) {
                return cityState
            }

            return mapItem.name
        } catch {
            return nil
        }
    }

    private static func conciseCityState(from address: String) -> String? {
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

    private static func cleanAddressPart(_ part: String) -> String {
        part
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^\d{4,6}\s*"#,
                with: "",
                options: .regularExpression
            )
    }
}
