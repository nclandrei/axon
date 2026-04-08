// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "axon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "axon",
            path: "Sources/axon",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
