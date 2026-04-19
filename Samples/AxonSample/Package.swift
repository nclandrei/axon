// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AxonSample",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AxonSample", targets: ["AxonSample"])
    ],
    targets: [
        .executableTarget(
            name: "AxonSample",
            path: "Sources/AxonSample"
        )
    ]
)
