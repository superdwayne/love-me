// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoveMeDaemon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LoveMeDaemon",
            path: "Sources/LoveMeDaemon",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
