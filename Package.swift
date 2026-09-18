// swift-tools-version: 6.0
import PackageDescription

// The app itself is an Xcode project (visionOS), but its logic — the two API
// clients, the session engine, the Markdown splitter — is plain Swift. Exposing
// it as a package means the tests run on the Mac in seconds, with no simulator
// in the way.
let package = Package(
    name: "ParallaxCore",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "ParallaxCore",
            path: "Sources",
            exclude: ["App", "Views", "Support", "Resources", "Design/ParallaxMark.swift"],
            sources: ["Models", "Services", "Store", "Design/Palette.swift"]
        ),
        .testTarget(
            name: "ParallaxCoreTests",
            dependencies: ["ParallaxCore"],
            path: "Tests"
        ),
    ]
)
