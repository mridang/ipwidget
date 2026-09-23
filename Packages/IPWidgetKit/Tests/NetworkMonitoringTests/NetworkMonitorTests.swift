import XCTest

@testable import NetworkMonitoring

final class NetworkMonitorTests: XCTestCase {
    /// Records calls without relying on the real `NWPathMonitor` callback,
    /// which fires on its own schedule and would otherwise race these
    /// assertions. Guarded by a lock since it's shared with `@Sendable` code.
    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func record() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func testIsConnectedDefaultsToTrue() {
        let monitor = NetworkMonitor(debounceInterval: 100, onReload: {})
        XCTAssertTrue(monitor.isConnected)
    }

    func testReloadNowInvokesOnReloadImmediately() {
        let recorder = CallRecorder()
        // A long debounce keeps the real path-monitor's own callback from
        // firing during this synchronous assertion window.
        let monitor = NetworkMonitor(debounceInterval: 100, onReload: { recorder.record() })

        monitor.reloadNow()

        XCTAssertEqual(recorder.callCount, 1)
    }

    func testReloadNowBypassesDebounce() {
        let recorder = CallRecorder()
        let monitor = NetworkMonitor(debounceInterval: 100, onReload: { recorder.record() })

        // Two immediate calls both fire synchronously — reloadNow() is not
        // subject to the debounce that coalesces path-change callbacks.
        monitor.reloadNow()
        monitor.reloadNow()

        XCTAssertEqual(recorder.callCount, 2)
    }
}
