/// The resolved identity of a public IP address: the address itself plus
/// whatever geolocation could be determined for it.
public struct IPInfo: Sendable, Equatable {
    public let address: String
    public let countryCode: String?
    public let countryName: String?
    public let coordinate: Coordinate?

    /// Whether `address` is an IPv6 address (delegates to the shared helper).
    public var isIPv6: Bool { isIPv6Address(address) }

    public init(
        address: String,
        countryCode: String? = nil,
        countryName: String? = nil,
        coordinate: Coordinate? = nil
    ) {
        self.address = address
        self.countryCode = countryCode
        self.countryName = countryName
        self.coordinate = coordinate
    }
}

/// A plain latitude/longitude pair. Deliberately not `CLLocationCoordinate2D`:
/// this module has no CoreLocation/MapKit dependency at all, so callers that
/// do use MapKit convert at their own call site.
public struct Coordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
