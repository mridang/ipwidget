/// Whether an IP address string is IPv6. IPv6 literals contain colons; IPv4
/// dotted-quad addresses never do.
public func isIPv6Address(_ address: String) -> Bool {
    address.contains(":")
}

/// Converts an ISO 3166-1 alpha-2 country code into its flag emoji by offsetting
/// each ASCII letter into the Regional Indicator Symbol range. Returns a neutral
/// white flag for nil, non-two-letter, or non-alphabetic input.
public func flagEmoji(for countryCode: String?) -> String {
    guard let code = countryCode?.uppercased(), code.count == 2, code.allSatisfy({ $0.isLetter }) else {
        return "🏳️"
    }
    let base: UInt32 = 127397  // 0x1F1E6 ('🇦') minus 'A'.
    var scalars = String.UnicodeScalarView()
    for scalar in code.unicodeScalars {
        if let flagScalar = Unicode.Scalar(base + scalar.value) { scalars.append(flagScalar) }
    }
    return String(scalars)
}
