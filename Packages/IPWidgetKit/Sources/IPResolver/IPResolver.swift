/// Resolves the public IP and its geolocation.
///
/// Geolocation is best-effort: if it fails, `resolve()` still returns the IP,
/// just without country/coordinate — losing the map is better than losing the
/// one thing that matters most, the address itself.
public struct IPResolver: Sendable {
    private let ipProvider: PublicIPProviding
    private let geolocator: IPGeolocating

    public init(
        ipProvider: PublicIPProviding = IpifyPublicIPProvider(),
        geolocator: IPGeolocating = IPWhoIsGeolocator()
    ) {
        self.ipProvider = ipProvider
        self.geolocator = geolocator
    }

    public func resolve() async throws -> IPInfo {
        let address = try await ipProvider.fetchPublicIP()

        guard let geo = try? await geolocator.locate(address) else {
            return IPInfo(address: address)
        }
        return IPInfo(
            address: address,
            countryCode: geo.countryCode,
            countryName: geo.countryName,
            coordinate: geo.coordinate
        )
    }
}
