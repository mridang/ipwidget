//
//  IPWidget.swift
//  IPWidgetExtension
//
//  The widget: refresh timeline and a SwiftUI view styled to feel native to
//  macOS. The IP/geolocation resolving and map rendering live in the
//  IPWidgetKit local package (IPResolver + MapSnapshotting) — this file is
//  just the WidgetKit/SwiftUI glue on top of them.
//

import CoreLocation
import IPResolver
import MapKit
import MapSnapshotting
import SwiftUI
import WidgetKit

#if canImport(AppKit)
    import AppKit
#endif

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> IPEntry {
        IPEntry(
            date: Date(),
            info: IPInfo(address: "2606:4700:4700::1111", countryCode: "US", countryName: "United States"),
            mapImageData: nil,
            errorMessage: nil
        )
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
            let next =
                Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry(mapSize: CGSize) async -> IPEntry {
        do {
            let info = try await IPResolver().resolve()

            // Frame the map to the whole country; fall back to a wide view around
            // the IP coordinate only if we can't resolve the country.
            var region: MKCoordinateRegion?
            if let name = info.countryName {
                region = await CountryFramer.region(forCountryNamed: name)
            }
            if region == nil, let coordinate = info.coordinate {
                region = CountryFramer.wideRegion(around: coordinate.clLocationCoordinate)
            }

            var mapData: Data?
            if let region {
                let pixelSize = CGSize(
                    width: max(mapSize.width, 170) * 2,
                    height: max(mapSize.height, 170) * 2
                )
                mapData = await MapRenderer.snapshot(region: region, size: pixelSize)
            }

            return IPEntry(date: Date(), info: info, mapImageData: mapData, errorMessage: nil)
        } catch {
            return IPEntry(date: Date(), info: nil, mapImageData: nil, errorMessage: "No connection")
        }
    }
}

/// One point on the widget's timeline: resolved `info` plus an optional
/// pre-rendered map background, or an `errorMessage` when the lookup failed.
struct IPEntry: TimelineEntry {
    let date: Date
    let info: IPInfo?
    let mapImageData: Data?
    let errorMessage: String?
}

extension Coordinate {
    /// Converts to the MapKit/CoreLocation type at the one call site that
    /// needs it — IPResolver itself has no MapKit/CoreLocation dependency.
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.17),
                        Color(red: 0.10, green: 0.13, blue: 0.24),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Darken the top (header) and, more strongly, the bottom (address)
            // so the white text stays legible over any part of the map.
            LinearGradient(
                colors: [.black.opacity(0.30), .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
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
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.55, blue: 1.0),
                                Color(red: 0.10, green: 0.78, blue: 0.95),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
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
                Text(info.address)
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
    IPEntry(
        date: .now,
        info: IPInfo(address: "2606:4700:4700::1111", countryCode: "GB", countryName: "United Kingdom"),
        mapImageData: nil,
        errorMessage: nil
    )
    IPEntry(
        date: .now,
        info: IPInfo(address: "203.0.113.42", countryCode: "US", countryName: "United States"),
        mapImageData: nil,
        errorMessage: nil
    )
    IPEntry(date: .now, info: nil, mapImageData: nil, errorMessage: "No connection")
}

#Preview("Large", as: .systemLarge) {
    IPWidget()
} timeline: {
    IPEntry(
        date: .now,
        info: IPInfo(address: "2606:4700:4700::1111", countryCode: "GB", countryName: "United Kingdom"),
        mapImageData: nil,
        errorMessage: nil
    )
    IPEntry(
        date: .now,
        info: IPInfo(address: "203.0.113.42", countryCode: "US", countryName: "United States"),
        mapImageData: nil,
        errorMessage: nil
    )
}
