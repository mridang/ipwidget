import Foundation
import Network
import WidgetKit

/// Observable wrapper around `NWPathMonitor`. Publishes a simple connectivity
/// flag and triggers a (debounced) reload callback whenever the network path
/// changes in any way.
///
/// Crucially this reloads on *any* path change, not just connectivity
/// gained/lost: switching Wi-Fi networks or toggling a VPN keeps the status
/// "satisfied" yet changes the public IP, and those are the cases that matter
/// most. A short debounce coalesces the burst of callbacks a single
/// transition produces into one reload.
///
/// `@unchecked Sendable`: `NWPathMonitor`'s `pathUpdateHandler` is itself
/// `@Sendable`, so this type must be able to cross into it. Its mutable state
/// is manually synchronized rather than compiler-checked: `isConnected` is
/// only ever written via `DispatchQueue.main.async`, and `pendingReload` is
/// only ever touched from `queue`, the monitor's own private serial queue.
public final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ng.mrida.IPWidget.NetworkMonitor")
    private let debounceInterval: TimeInterval
    private let onReload: @Sendable () -> Void

    /// Pending debounced reload, cancelled and rescheduled on each change so a
    /// rapid series of path updates results in a single reload.
    private var pendingReload: DispatchWorkItem?

    /// - Parameters:
    ///   - debounceInterval: how long to wait after the last path change
    ///     before reloading. Long enough to absorb a transition's burst of
    ///     callbacks, short enough to feel immediate.
    ///   - onReload: called (debounced) whenever the network path changes.
    ///     Defaults to reloading all WidgetKit timelines; inject a fake in
    ///     tests to verify debounce behavior without touching WidgetKit.
    public init(
        debounceInterval: TimeInterval = 1.5,
        onReload: @escaping @Sendable () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.debounceInterval = debounceInterval
        self.onReload = onReload

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isConnected = (path.status == .satisfied)
            }

            self.scheduleReload()
        }
        monitor.start(queue: queue)
    }

    /// Force an immediate reload, bypassing the debounce.
    public func reloadNow() {
        onReload()
    }

    /// Debounce: cancel any queued reload and schedule a fresh one. Runs on
    /// the monitor's own serial queue, so the work items don't race.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [onReload] in onReload() }
        pendingReload = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
