// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NXPlayKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NXPlayKit", targets: ["NXPlayKit"])
    ],
    targets: [
        .target(name: "NXPlayKit"),
        .testTarget(name: "NXPlayKitTests", dependencies: ["NXPlayKit"]),
    ]
)
