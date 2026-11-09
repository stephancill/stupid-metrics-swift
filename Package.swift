// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StupidMetrics",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StupidMetrics", targets: ["StupidMetrics"]),
    ],
    targets: [
        .target(name: "StupidMetrics"),
        .testTarget(name: "StupidMetricsTests", dependencies: ["StupidMetrics"]),
    ]
)
