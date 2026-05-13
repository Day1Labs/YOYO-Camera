import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?
    var onLocationUpdated: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    /// Permissions
    func authorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return manager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Monitoring lifecycle
    func startMonitoring() {
        // ifnot yet; can thentrigger
        let status = authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            let status: CLAuthorizationStatus = authorizationStatus()
            guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
            manager.startUpdatingLocation()
        case .notDetermined:
            requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        if #available(iOS 9.0, *) {
            manager.requestLocation()
        } else {
            manager.startUpdatingLocation()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        onAuthorizationChanged?(authorizationStatus())
        // If one-shot was requested pre-authorization, CLLocationManager will call didUpdate once granted
    }

    func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        onAuthorizationChanged?(status)
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        currentLocation = last
        onLocationUpdated?(last)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        // Keep minimal logging; upstream can decide how to surface errors
        print("位置获取失败: \(error.localizedDescription)")
    }
}
