import XCTest

@testable import IPResolver

final class IPResolverTests: XCTestCase {

    // MARK: isIPv6Address

    func testIPv4IsNotIPv6() {
        XCTAssertFalse(isIPv6Address("203.0.113.42"))
        XCTAssertFalse(isIPv6Address("8.8.8.8"))
    }

    func testIPv6IsDetected() {
        XCTAssertTrue(isIPv6Address("2606:4700:4700::1111"))
        XCTAssertTrue(isIPv6Address("::1"))
        XCTAssertTrue(isIPv6Address("fe80::1ff:fe23:4567:890a"))
    }

    // MARK: flagEmoji

    func testFlagEmojiForValidCode() {
        // 🇦🇺 is two regional-indicator scalars: U+1F1E6 (AU's 'A') + U+1F1FA ('U').
        XCTAssertEqual(flagEmoji(for: "AU"), "\u{1F1E6}\u{1F1FA}")
        XCTAssertEqual(flagEmoji(for: "GB"), "\u{1F1EC}\u{1F1E7}")
    }

    func testFlagEmojiLowercaseIsNormalized() {
        XCTAssertEqual(flagEmoji(for: "au"), flagEmoji(for: "AU"))
    }

    func testFlagEmojiFallsBackForInvalidInput() {
        let whiteFlag = "🏳️"
        XCTAssertEqual(flagEmoji(for: nil), whiteFlag)
        XCTAssertEqual(flagEmoji(for: ""), whiteFlag)
        XCTAssertEqual(flagEmoji(for: "USA"), whiteFlag)  // 3 letters
        XCTAssertEqual(flagEmoji(for: "U1"), whiteFlag)  // non-alphabetic
        XCTAssertEqual(flagEmoji(for: "??"), whiteFlag)  // the sentinel from geo failures
    }

    // MARK: IPResolver

    private struct FakeIPProvider: PublicIPProviding {
        let result: Result<String, Error>
        func fetchPublicIP() async throws -> String { try result.get() }
    }

    private struct FakeGeolocator: IPGeolocating {
        let result: Result<IPGeolocation?, Error>
        func locate(_ address: String) async throws -> IPGeolocation? { try result.get() }
    }

    func testResolveReturnsIPWithGeolocation() async throws {
        let resolver = IPResolver(
            ipProvider: FakeIPProvider(result: .success("203.0.113.42")),
            geolocator: FakeGeolocator(
                result: .success(
                    IPGeolocation(
                        countryCode: "US",
                        countryName: "United States",
                        coordinate: Coordinate(latitude: 37.0, longitude: -122.0)
                    )
                )
            )
        )

        let info = try await resolver.resolve()

        XCTAssertEqual(info.address, "203.0.113.42")
        XCTAssertEqual(info.countryCode, "US")
        XCTAssertEqual(info.countryName, "United States")
        XCTAssertEqual(info.coordinate, Coordinate(latitude: 37.0, longitude: -122.0))
        XCTAssertFalse(info.isIPv6)
    }

    func testResolveFallsBackWhenGeolocationFails() async throws {
        let resolver = IPResolver(
            ipProvider: FakeIPProvider(result: .success("2606:4700:4700::1111")),
            geolocator: FakeGeolocator(result: .failure(IPResolverError("geolocation unavailable")))
        )

        let info = try await resolver.resolve()

        XCTAssertEqual(info.address, "2606:4700:4700::1111")
        XCTAssertNil(info.countryCode)
        XCTAssertNil(info.countryName)
        XCTAssertNil(info.coordinate)
        XCTAssertTrue(info.isIPv6)
    }

    func testResolveThrowsWhenIPProviderFails() async {
        let resolver = IPResolver(
            ipProvider: FakeIPProvider(result: .failure(IPResolverError("network unavailable"))),
            geolocator: FakeGeolocator(result: .success(nil))
        )

        await assertThrowsErrorAsync(try await resolver.resolve()) { error in
            XCTAssertEqual((error as? IPResolverError)?.message, "network unavailable")
        }
    }
}

/// `XCTAssertThrowsError` has no async overload, so this small helper awaits
/// the expression first and asserts on the thrown error the same way.
func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
