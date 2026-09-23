import Foundation

/// Resolves the caller's own public IP address.
public protocol PublicIPProviding: Sendable {
    func fetchPublicIP() async throws -> String
}

/// Default provider: api64.ipify.org returns the public IP over IPv6 when the
/// machine has it, otherwise IPv4 — so a single call tells us both the
/// address and the protocol (IPv6 literals contain colons).
public struct IpifyPublicIPProvider: PublicIPProviding {
    private let endpoint = "https://api64.ipify.org"

    public init() {}

    public func fetchPublicIP() async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw IPResolverError("invalid URL: \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IPResolverError("bad response fetching public IP")
        }
        guard
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else {
            throw IPResolverError("empty or undecodable response fetching public IP")
        }
        return text
    }
}
