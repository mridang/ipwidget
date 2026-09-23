import Foundation

/// Resolves country + coordinate for a given IP address.
public protocol IPGeolocating: Sendable {
    /// Returns `nil` when the lookup succeeds but yields no usable result;
    /// throws when the lookup itself fails (network, bad response, decode).
    func locate(_ address: String) async throws -> IPGeolocation?
}

public struct IPGeolocation: Sendable, Equatable {
    public let countryCode: String?
    public let countryName: String?
    public let coordinate: Coordinate?

    public init(countryCode: String?, countryName: String?, coordinate: Coordinate?) {
        self.countryCode = countryCode
        self.countryName = countryName
        self.coordinate = coordinate
    }
}

/// ipwho.is response shape. File-private (not nested in `IPWhoIsGeolocator`)
/// so its `CodingKeys` stays at one level of nesting.
private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let country: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case success, country, latitude, longitude
        case countryCode = "country_code"
    }
}

/// Default geolocator: ipwho.is resolves an IP to its country and coordinates.
public struct IPWhoIsGeolocator: IPGeolocating {
    public init() {}

    public func locate(_ address: String) async throws -> IPGeolocation? {
        guard let url = URL(string: "https://ipwho.is/\(address)") else {
            throw IPResolverError("invalid URL for address: \(address)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IPResolverError("bad response geolocating \(address)")
        }
        let decoded = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
        guard decoded.success != false else { return nil }

        let coordinate: Coordinate? = {
            guard let lat = decoded.latitude, let lon = decoded.longitude else { return nil }
            return Coordinate(latitude: lat, longitude: lon)
        }()
        return IPGeolocation(countryCode: decoded.countryCode, countryName: decoded.country, coordinate: coordinate)
    }
}
