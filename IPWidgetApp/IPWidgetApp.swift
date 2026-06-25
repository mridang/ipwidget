//
//  IPWidgetApp.swift
//  IPWidget
//
//  A headless background agent — no window, no Dock icon (LSUIElement), and no
//  menu-bar item. It exists solely to host the widget extension and to run the
//  network-change service that reloads the widget. It registers itself to launch
//  at login so the service persists silently.
//

import SwiftUI
import AppKit
import ServiceManagement

@main
struct IPWidgetHostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // SwiftUI requires a Scene, but a Settings scene never shows a window on
        // its own — and with no app menu (we're an LSUIElement agent) there's no
        // way to open it. The result is a process with zero visible UI.
        Settings { EmptyView() }
    }
}

/// Owns the background network service and keeps the agent registered to launch
/// at login. No UI of any kind.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Starts monitoring on creation and lives for the process lifetime.
    private let monitor = NetworkMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Persist the agent across logins. Idempotent — only register if it
        // isn't already enabled.
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }
}
