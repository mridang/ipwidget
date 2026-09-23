import CoreImage
import XCTest

@testable import MapSnapshotting

final class MapRendererStyleTests: XCTestCase {
    func testDefaultStyleMatchesDocumentedPalette() {
        let style = MapRenderer.Style.default

        XCTAssertEqual(style.shadow, CIColor(red: 0.05, green: 0.07, blue: 0.17))
        XCTAssertEqual(style.highlight, CIColor(red: 0.45, green: 0.66, blue: 0.92))
        XCTAssertEqual(style.jpegCompressionQuality, 0.9)
    }

    func testCustomStyleRoundTrips() {
        let shadow = CIColor(red: 0, green: 0, blue: 0)
        let highlight = CIColor(red: 1, green: 1, blue: 1)
        let style = MapRenderer.Style(shadow: shadow, highlight: highlight, jpegCompressionQuality: 0.5)

        XCTAssertEqual(style.shadow, shadow)
        XCTAssertEqual(style.highlight, highlight)
        XCTAssertEqual(style.jpegCompressionQuality, 0.5)
    }
}
