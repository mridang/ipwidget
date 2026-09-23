import CoreLocation
import MapKit

/// Resolves a country to a map region that frames the *whole country*, so the
/// background reads as "your country" rather than a slice of coastline around
/// your city. Uses MapKit's local search, whose bounding region for a country
/// name covers the country.
public enum CountryFramer {
    /// The country's bounding region, or nil if the search yields nothing.
    /// This is a deliberate soft failure, not an omission: the caller falls
    /// back to `wideRegion(around:)` rather than showing no map at all.
    public static func region(forCountryNamed name: String) async -> MKCoordinateRegion? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.boundingRegion
        } catch {
            return nil
        }
    }

    /// Fallback when the country can't be framed: a wide view around the IP
    /// coordinate. Still better than a missing map.
    public static func wideRegion(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000_000,
            longitudinalMeters: 3_000_000
        )
    }
}
