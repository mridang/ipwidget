//
//  IPWidget.swift
//  IPWidgetExtension
//
//  The widget: data model, network fetch, a ready-made MapKit map render, the
//  refresh timeline, and a SwiftUI view styled to feel native to macOS.
//
//  IP source: api64.ipify.org returns the public IP over IPv6 when the machine
//  has it, otherwise IPv4 — so a single call tells us both the address and the
//  protocol (IPv6 literals contain colons). A second lookup (ipwho.is)
//  resolves the country and coordinates used to frame the map.
//

import WidgetKit
import SwiftUI
import MapKit
import CoreLocation
import CoreImage
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Model

/// The displayable identity shown in the widget. Only plain values live here so
/// the entry stays trivially serializable; the map is pre-rendered into bytes.
struct IPInfo {
    let ip: String
    let countryCode: String?
    let countryName: String?

    /// Whether `ip` is an IPv6 address (delegates to the shared helper).
    var isIPv6: Bool { isIPv6Address(ip) }
}

/// One point on the widget's timeline: resolved `info` plus an optional
/// pre-rendered map background, or an `errorMessage` when the lookup failed.
struct IPEntry: TimelineEntry {
    let date: Date
    let info: IPInfo?
    let mapImageData: Data?
    let errorMessage: String?
}

// MARK: - Networking

/// Resolves the public IP and its geolocation. Two calls: ipify for the
/// address/protocol, ipwho.is for country + coordinates.
enum IPFetcher {
    /// Everything the provider needs: what to display, and where to center the
    /// map (kept separate so it doesn't have to be stored in the entry).
    struct Resolved {
        let info: IPInfo
        let coordinate: CLLocationCoordinate2D?
    }

    private struct Geo: Decodable {
        let success: Bool?
        let country: String?
        let country_code: String?
        let latitude: Double?
        let longitude: Double?
    }

    static func fetch() async throws -> Resolved {
        let ip = try await string(from: "https://api64.ipify.org")

        // Geolocation is best-effort: if it fails we still show the IP, just
        // without a map.
        if let geo = try? await geo(forIP: ip),
           geo.success != false {
            let coordinate: CLLocationCoordinate2D? = {
                guard let lat = geo.latitude, let lon = geo.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }()
            let info = IPInfo(ip: ip, countryCode: geo.country_code, countryName: geo.country)
            return Resolved(info: info, coordinate: coordinate)
        }

        return Resolved(info: IPInfo(ip: ip, countryCode: nil, countryName: nil), coordinate: nil)
    }

    /// Fetches a URL and returns its body as a trimmed string.
    private static func string(from urlString: String) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request(urlString))
        try validate(response)
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw URLError(.cannotDecodeContentData)
        }
        return text
    }

    private static func geo(forIP ip: String) async throws -> Geo {
        let (data, response) = try await URLSession.shared.data(for: request("https://ipwho.is/\(ip)"))
        try validate(response)
        return try JSONDecoder().decode(Geo.self, from: data)
    }

    private static func request(_ urlString: String) -> URLRequest {
        var request = URLRequest(url: URL(string: urlString)!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Map render

/// Renders a MapKit satellite snapshot centered on a coordinate, then recolors
/// it into a two-tone "duotone" map: deep indigo shadows fading to a soft blue.
/// Apple's own map tiles (no hand-rolled geometry), but processed so they read
/// as a designed map rather than a photograph — and with no place labels.
enum MapRenderer {
    /// Duotone endpoints: shadows (sea) and highlights (land).
    private static let shadow = CIColor(red: 0.05, green: 0.07, blue: 0.17)
    private static let highlight = CIColor(red: 0.45, green: 0.66, blue: 0.92)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func snapshot(region: MKCoordinateRegion, size: CGSize) async -> Data? {
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
                continuation.resume(returning: duotone(snapshot.image))
            }
        }
    }

    /// Maps the snapshot to grayscale, then remaps black→indigo / white→blue
    /// via CIFalseColor, and encodes the result as JPEG bytes.
    private static func duotone(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else { return nil }

        let source = CIImage(cgImage: cgImage)
        let mono = source.applyingFilter("CIPhotoEffectMono")
        guard let falseColor = CIFilter(name: "CIFalseColor") else { return nil }
        falseColor.setValue(mono, forKey: kCIInputImageKey)
        falseColor.setValue(shadow, forKey: "inputColor0")
        falseColor.setValue(highlight, forKey: "inputColor1")

        guard let output = falseColor.outputImage?.cropped(to: source.extent),
              let result = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return NSBitmapImageRep(cgImage: result)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

/// Resolves a country to a map region that frames the *whole country*, so the
/// background reads as "your country" rather than a slice of coastline around
/// your city. Uses MapKit's local search, whose bounding region for a country
/// name covers the country.
enum CountryFramer {
    /// The country's bounding region, or nil if the search yields nothing.
    static func region(forCountryNamed name: String) async -> MKCoordinateRegion? {
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
    static func wideRegion(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate,
                           latitudinalMeters: 3_000_000,
                           longitudinalMeters: 3_000_000)
    }
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> IPEntry {
        IPEntry(date: Date(),
                info: IPInfo(ip: "2606:4700:4700::1111", countryCode: "US", countryName: "United States"),
                mapImageData: nil, errorMessage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (IPEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await currentEntry(mapSize: context.displaySize)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IPEntry>) -> Void) {
        Task {
            let entry = await currentEntry(mapSize: context.displaySize)
            // Fallback cadence only — the menu-bar agent reloads us immediately
            // whenever the network path actually changes.
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry(mapSize: CGSize) async -> IPEntry {
        do {
            let resolved = try await IPFetcher.fetch()

            // Frame the map to the whole country; fall back to a wide view around
            // the IP coordinate only if we can't resolve the country.
            var region: MKCoordinateRegion?
            if let name = resolved.info.countryName {
                region = await CountryFramer.region(forCountryNamed: name)
            }
            if region == nil, let coordinate = resolved.coordinate {
                region = CountryFramer.wideRegion(around: coordinate)
            }

            var mapData: Data?
            if let region {
                let pixelSize = CGSize(width: max(mapSize.width, 170) * 2,
                                       height: max(mapSize.height, 170) * 2)
                mapData = await MapRenderer.snapshot(region: region, size: pixelSize)
            }

            return IPEntry(date: Date(), info: resolved.info, mapImageData: mapData, errorMessage: nil)
        } catch {
            return IPEntry(date: Date(), info: nil, mapImageData: nil, errorMessage: "No connection")
        }
    }
}

// MARK: - Views

/// The map background (or a system-toned gradient fallback) with gradient
/// scrims that keep the header and card legible over any map.
private struct MapBackground: View {
    let imageData: Data?

    var body: some View {
        ZStack {
            if let imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback matches the duotone palette so a missing map still
                // looks intentional rather than a different design.
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.07, blue: 0.17),
                             Color(red: 0.10, green: 0.13, blue: 0.24)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Darken the top (header) and, more strongly, the bottom (address)
            // so the white text stays legible over any part of the map.
            LinearGradient(colors: [.black.opacity(0.30), .clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// A per-country flag rendered as a rounded-rectangle chip with a hairline
/// border — the way macOS System Settings presents region flags, so it reads as
/// a designed element rather than a raw emoji.
private struct FlagChip: View {
    let countryCode: String?
    var large: Bool = false

    var body: some View {
        // Plain emoji flag, sized to the family, with a soft shadow so it stays
        // legible over the map.
        Text(flagEmoji(for: countryCode))
            .font(.system(size: large ? 33 : 22))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
    }
}

/// A small protocol pill. IPv6 is celebrated with a vibrant accent capsule;
/// IPv4 sits quietly in a system material.
private struct ProtocolBadge: View {
    let isIPv6: Bool
    var large: Bool = false

    var body: some View {
        let hPad: CGFloat = large ? 11 : 8
        let vPad: CGFloat = large ? 5 : 3

        Group {
            if isIPv6 {
                Text("IPv6")
                    .foregroundStyle(.white)
                    .padding(.horizontal, hPad)
                    .padding(.vertical, vPad)
                    .background(
                        LinearGradient(colors: [Color(red: 0.20, green: 0.55, blue: 1.0),
                                                Color(red: 0.10, green: 0.78, blue: 0.95)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            } else {
                Text("IPv4")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, hPad)
                    .padding(.vertical, vPad)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .font(.system(size: large ? 14 : 11, weight: .bold, design: .rounded))
    }
}

/// The widget's foreground: the country flag on the left and the protocol badge
/// on the right up top, with the address and country anchored to the bottom —
/// set directly on the duotone map (the bottom scrim carries the contrast).
struct IPWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: IPEntry

    /// The large family gets a tall 2×2 canvas, so everything scales up.
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: isLarge ? 12 : 8)
            footer
        }
        .padding(isLarge ? 18 : 14)
    }

    private var header: some View {
        HStack(alignment: .center) {
            if let info = entry.info {
                FlagChip(countryCode: info.countryCode, large: isLarge)
            }
            Spacer()
            if let info = entry.info {
                ProtocolBadge(isIPv6: info.isIPv6, large: isLarge)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: isLarge ? 6 : 3) {
            if let info = entry.info {
                Text(info.ip)
                    .font(.system(size: isLarge ? 25 : 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                Text(info.countryName ?? "Unknown location")
                    .font(isLarge ? .title3 : .caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            } else {
                Label(entry.errorMessage ?? "Unavailable", systemImage: "wifi.slash")
                    .font((isLarge ? Font.title3 : Font.callout).weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct IPWidget: Widget {
    private let kind = "IPWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            IPWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    MapBackground(imageData: entry.mapImageData)
                }
        }
        .configurationDisplayName("IP Address")
        .description("Your public IP and country on a map, with an IPv4/IPv6 badge. Updates when the network changes.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    IPWidget()
} timeline: {
    IPEntry(date: .now, info: IPInfo(ip: "2606:4700:4700::1111", countryCode: "GB", countryName: "United Kingdom"), mapImageData: nil, errorMessage: nil)
    IPEntry(date: .now, info: IPInfo(ip: "203.0.113.42", countryCode: "US", countryName: "United States"), mapImageData: nil, errorMessage: nil)
    IPEntry(date: .now, info: nil, mapImageData: nil, errorMessage: "No connection")
}

#Preview("Large", as: .systemLarge) {
    IPWidget()
} timeline: {
    IPEntry(date: .now, info: IPInfo(ip: "2606:4700:4700::1111", countryCode: "GB", countryName: "United Kingdom"), mapImageData: nil, errorMessage: nil)
    IPEntry(date: .now, info: IPInfo(ip: "203.0.113.42", countryCode: "US", countryName: "United States"), mapImageData: nil, errorMessage: nil)
}
