// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SolaceDaemon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SolaceDaemon",
            path: "Sources/SolaceDaemon",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
