import Foundation
import CoreLocation
import Observation

/// Who you are to the people you climb with: a first name and, if you opt in, a city.
/// Never a gym, never an address. Location is resolved once per launch and only
/// while the app is in use.
@MainActor
@Observable
final class Identity: NSObject, CLLocationManagerDelegate {
    static let shared = Identity()

    var name: String { didSet { defaults.set(name, forKey: "name") } }
    var shareCity: Bool {
        didSet {
            defaults.set(shareCity, forKey: "shareCity")
            if shareCity { requestCity() } else { city = nil }
        }
    }
    var city: String? { didSet { defaults.set(city, forKey: "city") } }
    enum LocationState: Equatable { case idle, asking, locating, found, denied, failed }
    var locationState: LocationState = .idle
    var age: Int { didSet { defaults.set(age, forKey: "age") } }
    var weightKg: Double { didSet { defaults.set(weightKg, forKey: "weightKg") } }
    let installId: String

    private let defaults = UserDefaults.standard
    private let location = CLLocationManager()

    private override init() {
        name = defaults.string(forKey: "name") ?? ""
        shareCity = defaults.object(forKey: "shareCity") as? Bool ?? true
        city = defaults.string(forKey: "city")
        age = defaults.object(forKey: "age") as? Int ?? 30
        weightKg = defaults.object(forKey: "weightKg") as? Double ?? 75
        if let id = defaults.string(forKey: "installId") {
            installId = id
        } else {
            let id = UUID().uuidString.lowercased()
            defaults.set(id, forKey: "installId")
            installId = id
        }
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var publicCity: String? { shareCity ? city : nil }

    func requestCity() {
        guard shareCity else { locationState = .idle; return }
        switch location.authorizationStatus {
        case .notDetermined:
            locationState = .asking
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationState = city == nil ? .locating : .found
            location.requestLocation()
        default:
            locationState = .denied
        }
    }

    /// What the Setup screen shows next to "City".
    var cityLabel: String {
        if let city { return city }
        switch locationState {
        case .idle: return "Not requested"
        case .asking: return "Waiting for permission"
        case .locating: return "Locating…"
        case .found: return "Locating…"
        case .denied: return "Off in Settings → Privacy → Location"
        case .failed: return "Couldn't get a fix, retry later"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationState = .locating
                self.location.requestLocation()
            case .denied, .restricted:
                self.locationState = .denied
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task {
            let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            let mark = marks?.first
            let resolved = mark?.locality ?? mark?.subAdministrativeArea ?? mark?.administrativeArea
            await MainActor.run {
                if let resolved { self.city = resolved; self.locationState = .found } else { self.locationState = .failed }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in if self.city == nil { self.locationState = .failed } }
    }
}
