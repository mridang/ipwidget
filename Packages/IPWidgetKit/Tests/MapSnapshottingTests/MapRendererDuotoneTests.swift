import AppKit
import CoreImage
import XCTest

@testable import MapSnapshotting

final class MapRendererDuotoneTests: XCTestCase {
    private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = 8) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(red: red, green: green, blue: blue, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        return image
    }

    /// Decodes JPEG `data` and reads the color at its center pixel.
    private func centerColor(of data: Data) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    }

    func testDuotoneProducesDecodableJPEGOfTheSameSize() {
        let input = solidImage(red: 0.5, green: 0.5, blue: 0.5, size: 8)

        let data = MapRenderer.duotone(input, style: .default)

        let bitmap = data.flatMap { NSBitmapImageRep(data: $0) }
        XCTAssertNotNil(bitmap)
        XCTAssertEqual(bitmap?.pixelsWide, 8)
        XCTAssertEqual(bitmap?.pixelsHigh, 8)
    }

    func testBlackInputMapsTowardShadowColor() throws {
        let style = MapRenderer.Style(
            shadow: CIColor(red: 0, green: 0, blue: 1),  // blue shadow
            highlight: CIColor(red: 1, green: 0, blue: 0),  // red highlight
            jpegCompressionQuality: 1.0
        )
        let black = solidImage(red: 0, green: 0, blue: 0)

        let data = try XCTUnwrap(MapRenderer.duotone(black, style: style))
        let color = try XCTUnwrap(centerColor(of: data).map { $0.usingColorSpace(.deviceRGB) ?? $0 })

        // Black maps to luminance 0, which CIFalseColor renders as `shadow` (blue).
        XCTAssertGreaterThan(color.blueComponent, 0.7)
        XCTAssertLessThan(color.redComponent, 0.3)
    }

    func testWhiteInputMapsTowardHighlightColor() throws {
        let style = MapRenderer.Style(
            shadow: CIColor(red: 0, green: 0, blue: 1),  // blue shadow
            highlight: CIColor(red: 1, green: 0, blue: 0),  // red highlight
            jpegCompressionQuality: 1.0
        )
        let white = solidImage(red: 1, green: 1, blue: 1)

        let data = try XCTUnwrap(MapRenderer.duotone(white, style: style))
        let color = try XCTUnwrap(centerColor(of: data).map { $0.usingColorSpace(.deviceRGB) ?? $0 })

        // White maps to luminance 1, which CIFalseColor renders as `highlight` (red).
        XCTAssertGreaterThan(color.redComponent, 0.7)
        XCTAssertLessThan(color.blueComponent, 0.3)
    }

    func testDifferentStylesProduceDifferentOutput() throws {
        let input = solidImage(red: 0.5, green: 0.5, blue: 0.5)

        let a = try XCTUnwrap(MapRenderer.duotone(input, style: .default))
        let b = try XCTUnwrap(
            MapRenderer.duotone(
                input,
                style: MapRenderer.Style(
                    shadow: CIColor(red: 1, green: 0, blue: 0),
                    highlight: CIColor(red: 0, green: 1, blue: 0),
                    jpegCompressionQuality: 0.9
                )
            )
        )

        XCTAssertNotEqual(a, b)
    }
}
