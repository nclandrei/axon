// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "axon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "AxonLib",
            path: "Sources/AxonLib",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "axon",
            dependencies: ["AxonLib"],
            path: "Sources/axon",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "AxonUnitTests",
            dependencies: ["AxonLib"],
            path: "Tests/AxonUnitTests"
        ),
        .testTarget(
            name: "AxonIntegrationTests",
            dependencies: [],
            path: "Tests/AxonIntegrationTests"
        ),
        .testTarget(
            name: "AxonE2ETests",
            dependencies: [],
            path: "Tests/AxonE2ETests"
        ),
    ]
)
