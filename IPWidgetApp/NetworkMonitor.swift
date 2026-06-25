//
//  NetworkMonitor.swift
//  IPWidget
//
//  Watches the system network path and reloads the widget on every change.
//  This is the "service" that makes the widget feel live: WidgetKit only
//  refreshes a widget on its timeline schedule, so without this the public IP
//  could be stale for up to half an hour after switching networks.
//
//  Crucially we reload on *any* path change, not just connectivity gained/lost:
//  switching Wi-Fi networks or toggling a VPN keeps the status "satisfied" yet
//  changes the public IP, and those are the cases that matter most. A short
//  debounce coalesces the burst of callbacks a single transition produces into
//  one refresh.
//

import Foundation
import Network
import WidgetKit

/// Observable wrapper around `NWPathMonitor`. Publishes a simple connectivity
/// flag for the menu bar UI and triggers a (debounced) widget reload whenever
/// the network path changes in any way.
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ng.mrida.IPWidget.NetworkMonitor")

    /// Pending debounced reload, cancelled and rescheduled on each change so a
    /// rapid series of path updates results in a single widget refresh.
    private var pendingReload: DispatchWorkItem?

    /// How long to wait after the last path change before refreshing. Long
    /// enough to absorb a transition's burst of callbacks, short enough to feel
    /// immediate.
    private let debounceInterval: TimeInterval = 1.5

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            DispatchQueue.main.async {
                self.isConnected = (path.status == .satisfied)
            }

            self.scheduleReload()
        }
        monitor.start(queue: queue)
    }

    /// Force an immediate widget refresh (used by the menu bar's Refresh item).
    func reloadNow() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Debounce: cancel any queued reload and schedule a fresh one. Runs on the
    /// monitor's own serial queue, so the work items don't race.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        pendingReload = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
