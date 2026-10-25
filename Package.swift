// swift-tools-version: 6.0
// Editor tooling only (sourcekit-lsp): mirrors the Xcode app target so App/ resolves NXPlayKit.
// Build, run and test with the Xcode project and the package (bin/build, swift test --package-path
// Packages/NXPlayKit): SwiftPM doesn't bundle the app, its icon or nxplay.

import PackageDescription

let package = Package(
    name: "NXPlay",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "Packages/NXPlayKit")
    ],
    targets: [
        // Module name matches the app's PRODUCT_NAME ("NX Play").
        .executableTarget(
            name: "NX_Play",
            dependencies: [.product(name: "NXPlayKit", package: "NXPlayKit")],
            path: "App",
            exclude: ["Info.plist", "AppIcon.icon"]
        )
    ],
    swiftLanguageModes: [.v6]
)
