import Combine
import CoreLocation
import Foundation

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
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
            return "Location ready"
        }

        switch authorizationStatus {
        case .notDetermined:
            return "Location permission is needed for nearby matches."
        case .restricted, .denied:
            return "Location is off. Turn it on in Settings to see nearby matches."
        case .authorizedAlways, .authorizedWhenInUse:
            return "Finding your location..."
        @unknown default:
            return "Location status is unavailable."
        }
    }

    func requestLocation() {
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .restricted, .denied:
            authorizationStatus = manager.authorizationStatus
            errorMessage = "Allow location access in Settings to use distance matching."
        @unknown default:
            authorizationStatus = manager.authorizationStatus
            errorMessage = "Could not check location permission."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Could not get your location. \(error.localizedDescription)"
    }
}
