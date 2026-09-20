// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenTanEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpenTanEngine", targets: ["OpenTanEngine"])
    ],
    targets: [
        .target(name: "OpenTanEngine"),
        .testTarget(name: "OpenTanEngineTests", dependencies: ["OpenTanEngine"])
    ]
)
