//
//  IPWidgetTests.swift
//  IPWidgetTests
//
//  Unit tests for the pure logic in IPLogic.swift. That file is compiled
//  directly into this test bundle, so these run as fast, host-free logic tests
//  — no app launch, no network.
//

import XCTest

final class IPWidgetTests: XCTestCase {

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
        XCTAssertEqual(flagEmoji(for: "USA"), whiteFlag)   // 3 letters
        XCTAssertEqual(flagEmoji(for: "U1"), whiteFlag)    // non-alphabetic
        XCTAssertEqual(flagEmoji(for: "??"), whiteFlag)    // the sentinel from geo failures
    }
}
