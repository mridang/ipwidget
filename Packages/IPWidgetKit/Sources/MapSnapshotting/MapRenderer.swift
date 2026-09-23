import AppKit
import CoreImage
import MapKit

/// Renders a MapKit satellite snapshot centered on a coordinate, then recolors
/// it into a two-tone "duotone" map. Apple's own map tiles (no hand-rolled
/// geometry), but processed so they read as a designed map rather than a
/// photograph — and with no place labels.
public enum MapRenderer {
    /// A duotone palette plus JPEG encoding quality — a hook so a caller can
    /// render with a different look without touching this module, while the
    /// default reproduces today's exact "deep indigo shadows fading to a soft
    /// blue" appearance.
    public struct Style: Sendable {
        public let shadow: CIColor
        public let highlight: CIColor
        public let jpegCompressionQuality: Double

        public init(shadow: CIColor, highlight: CIColor, jpegCompressionQuality: Double) {
            self.shadow = shadow
            self.highlight = highlight
            self.jpegCompressionQuality = jpegCompressionQuality
        }

        public static let `default` = Style(
            shadow: CIColor(red: 0.05, green: 0.07, blue: 0.17),
            highlight: CIColor(red: 0.45, green: 0.66, blue: 0.92),
            jpegCompressionQuality: 0.9
        )
    }

    /// `CIContext` is documented by Apple as thread-safe and reusable across
    /// concurrent renders, so sharing one instance here is a deliberate,
    /// explicit decision rather than an accident of unchecked concurrency.
    private final class SharedContext: @unchecked Sendable {
        let context = CIContext(options: [.useSoftwareRenderer: false])
    }
    private static let shared = SharedContext()

    public static func snapshot(region: MKCoordinateRegion, size: CGSize, style: Style = .default) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        // Satellite imagery is the only ready-made MapKit style with no place
        // labels at all; we recolor it into the duotone below.
        options.appearance = NSAppearance(named: .darkAqua)
        options.preferredConfiguration = MKImageryMapConfiguration()

        let snapshotter = MKMapSnapshotter(options: options)
        return await withCheckedContinuation { continuation in
            snapshotter.start(with: .global(qos: .userInitiated)) { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: duotone(snapshot.image, style: style))
            }
        }
    }

    /// Maps the snapshot to grayscale, then remaps black→shadow / white→highlight
    /// via CIFalseColor, and encodes the result as JPEG bytes.
    ///
    /// Deliberately not `private`: this is the pure, deterministic half of
    /// `snapshot()` (no network, no MapKit) — `internal` lets the test target
    /// reach it via `@testable import` and exercise it directly, without the
    /// public API surface growing to expose it.
    static func duotone(_ image: NSImage, style: Style) -> Data? {
        guard let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let cgImage = bitmap.cgImage
        else { return nil }

        let source = CIImage(cgImage: cgImage)
        let mono = source.applyingFilter("CIPhotoEffectMono")
        guard let falseColor = CIFilter(name: "CIFalseColor") else { return nil }
        falseColor.setValue(mono, forKey: kCIInputImageKey)
        falseColor.setValue(style.shadow, forKey: "inputColor0")
        falseColor.setValue(style.highlight, forKey: "inputColor1")

        guard let output = falseColor.outputImage?.cropped(to: source.extent),
            let result = shared.context.createCGImage(output, from: output.extent)
        else { return nil }
        return NSBitmapImageRep(cgImage: result)
            .representation(using: .jpeg, properties: [.compressionFactor: style.jpegCompressionQuality])
    }
}
