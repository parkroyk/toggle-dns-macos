// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ToggleDNS",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ToggleDNS",
            path: "Sources/ToggleDNS"
        ),
        .testTarget(
            name: "ToggleDNSTests",
            dependencies: ["ToggleDNS"],
            path: "Tests/ToggleDNSTests"
        )
    ]
)
