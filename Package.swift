// swift-tools-version: 5.9
import PackageDescription

// The plugin is two modules: VideoTranscoderCore, the transcoder itself on AVFoundation alone, and VideoTranscoderPlugin, the
// Capacitor bridge to it. The core has a package of its own as well, ios/Package.swift, so that its tests run with `swift test`
// on a Mac, where the bridge (which needs UIKit through Capacitor) does not build.
let package = Package(
    name: "CapacitorVideoTranscoder",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorVideoTranscoder",
            targets: ["VideoTranscoderPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "VideoTranscoderCore",
            path: "ios/Sources/VideoTranscoderCore"),
        .target(
            name: "VideoTranscoderPlugin",
            dependencies: [
                "VideoTranscoderCore",
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/VideoTranscoderPlugin"),
        .testTarget(
            name: "VideoTranscoderCoreTests",
            dependencies: ["VideoTranscoderCore"],
            path: "ios/Tests/VideoTranscoderCoreTests"),
        .testTarget(
            name: "VideoTranscoderPluginTests",
            dependencies: ["VideoTranscoderPlugin", "VideoTranscoderCore"],
            path: "ios/Tests/VideoTranscoderPluginTests")
    ]
)
