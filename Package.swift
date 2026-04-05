// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WatchLink",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "WatchLinkCore", targets: ["WatchLinkCore"]),
        .library(name: "WatchLink", targets: ["WatchLink"]),
        .library(name: "WatchLinkHost", targets: ["WatchLinkHost"]),
    ],
    targets: [
        .target(
            name: "WatchLinkCore",
            path: "Sources/WatchLinkCore"
        ),
        .target(
            name: "WatchLink",
            dependencies: ["WatchLinkCore"],
            path: "Sources/WatchLink"
        ),
        .target(
            name: "WatchLinkHost",
            dependencies: ["WatchLinkCore"],
            path: "Sources/WatchLinkHost"
        ),
        .target(
            name: "WatchLinkTestSupport",
            dependencies: ["WatchLinkCore"],
            path: "Tests/WatchLinkTestSupport"
        ),
        .testTarget(
            name: "WatchLinkCoreTests",
            dependencies: ["WatchLinkCore", "WatchLinkTestSupport"],
            path: "Tests/WatchLinkCoreTests"
        ),
        .testTarget(
            name: "WatchLinkTests",
            dependencies: ["WatchLink", "WatchLinkCore", "WatchLinkTestSupport"],
            path: "Tests/WatchLinkTests"
        ),
    ]
)
