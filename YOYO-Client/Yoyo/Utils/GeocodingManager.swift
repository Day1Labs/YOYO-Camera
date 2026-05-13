import CoreLocation
import Foundation

final class GeocodingManager {
    static let shared = GeocodingManager()
    private let geocoder = CLGeocoder()

    private init() {}

    /// ()
    func reverseGeocode(_ location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                // : use,
                return placemark.locality ?? placemark.administrativeArea ?? placemark.name
            }
        } catch {
            print("Geocoding failed: \(error.localizedDescription)")
        }
        return nil
    }
}
