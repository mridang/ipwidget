/// Errors thrown while resolving the public IP or its geolocation.
public struct IPResolverError: Error, CustomStringConvertible, Sendable {
    /// Human-readable description of why resolution failed.
    public let message: String

    /// Creates an `IPResolverError` with the given `message`.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "IPResolverError: \(message)" }
    public var localizedDescription: String { description }
}
