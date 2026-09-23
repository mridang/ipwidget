import CoreLocation
import MapKit
import XCTest

@testable import MapSnapshotting

final class CountryFramerTests: XCTestCase {
    func testWideRegionIsCenteredOnTheGivenCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)

        let region = CountryFramer.wideRegion(around: coordinate)

        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.0001)
    }

    func testWideRegionMatchesA3000kmSpan() {
        let coordinate = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        let expected = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 3_000_000,
            longitudinalMeters: 3_000_000
        )

        let region = CountryFramer.wideRegion(around: coordinate)

        XCTAssertEqual(region.span.latitudeDelta, expected.span.latitudeDelta, accuracy: 0.0001)
        XCTAssertEqual(region.span.longitudeDelta, expected.span.longitudeDelta, accuracy: 0.0001)
    }
}
