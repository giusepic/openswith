// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpensWith",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OpensWith",
            path: "Sources/OpensWith"
        ),
        .testTarget(
            name: "OpensWithTests",
            dependencies: ["OpensWith"],
            path: "Tests/OpensWithTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
