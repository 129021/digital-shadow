// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DigitalShadow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DigitalShadow",
            path: "Sources",
            resources: [.process("../Resources")]
        ),
        .testTarget(
            name: "DigitalShadowTests",
            dependencies: ["DigitalShadow"],
            path: "Tests"
        ),
    ]
)
