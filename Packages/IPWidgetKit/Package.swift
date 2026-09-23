// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPWidgetKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IPResolver", targets: ["IPResolver"]),
        .library(name: "NetworkMonitoring", targets: ["NetworkMonitoring"]),
        .library(name: "MapSnapshotting", targets: ["MapSnapshotting"]),
    ],
    targets: [
        .target(name: "IPResolver"),
        .target(name: "NetworkMonitoring"),
        .target(name: "MapSnapshotting"),
        .testTarget(name: "IPResolverTests", dependencies: ["IPResolver"]),
        .testTarget(name: "NetworkMonitoringTests", dependencies: ["NetworkMonitoring"]),
        .testTarget(name: "MapSnapshottingTests", dependencies: ["MapSnapshotting"]),
    ]
)
