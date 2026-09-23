# IPWidget

A macOS WidgetKit widget that shows your public IP address, country, and
whether you're on IPv4 or IPv6, drawn over a duotone map of your country.

IPWidget ships as a headless background agent (no Dock icon, no menu bar
item) that hosts the widget extension and reloads it whenever your network
changes. There is no window and nothing to configure — install it, add the
widget to your desktop or Notification Center, and it keeps itself current.

### Why?

macOS has no built-in way to see your public IP at a glance, and most
"what's my IP" widgets are thin wrappers around a web view. IPWidget instead
runs a tiny native network service that resolves your public IP and country
locally and renders it as a proper WidgetKit widget, with no visible app
and no polling from a browser tab.

## Installation

Download the latest release from the
[Releases page](https://github.com/mridang/ipwidget/releases):

- **`IPWidget.pkg`** — a double-click installer that drops the app into
  `/Applications` and starts the background agent.
- **`IPWidget.zip`** — the raw `.app`, for a drag-install into
  `/Applications` instead.

The build is ad-hoc signed (a valid signature is required for the widget
extension to register with the system) but not notarized, since CI has no
Developer ID. macOS will flag it as from an "unidentified developer" —
right-click the app (or the `.pkg`) and choose **Open** to run it.

Once installed, add the widget from the widget gallery (right-click the
desktop or Notification Center → **Edit Widgets** → search "IPWidget").

## Development

Requires Xcode with the macOS SDK. Build the app with:

```bash
xcodebuild build \
    -project IPWidget.xcodeproj \
    -scheme IPWidget \
    -configuration Debug \
    -destination 'platform=macOS'
```

Run the unit tests (they live in the `IPWidgetKit` package, so this is a
plain `swift test` — no simulator, no `xcodebuild`):

```bash
swift test --package-path Packages/IPWidgetKit
```

To produce a release build and package it the same way CI does:

```bash
make package VERSION=<version>
```

This produces `IPWidget.pkg` and `IPWidget.zip` in the repo root.

## Project layout

- `IPWidgetApp` — the headless host app: registers itself to launch at
  login and starts the network-change monitor.
- `IPWidgetExtension` — the WidgetKit extension: the timeline provider and
  SwiftUI views.
- `Packages/IPWidgetKit` — the generic, UI-free logic, as a local Swift
  package: `IPResolver` (public IP + geolocation), `NetworkMonitoring`
  (network-path watching), `MapSnapshotting` (duotone map rendering). Has
  its own unit tests, runnable standalone with `swift test --package-path
  Packages/IPWidgetKit`.
- `installer` — the `postinstall` script embedded in the `.pkg` (registers
  the app with LaunchServices and launches it after install). The actual
  build/package recipe lives in the `Makefile`.

## Contributing

If you have suggestions for how this app could be improved, or
want to report a bug, open an issue - we'd love all and any
contributions.

## License

Apache License 2.0 © 2026 Mridang Agarwalla
