// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorPluginVideoTranscoder",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapacitorPluginVideoTranscoder",
            targets: ["VideoTranscoderPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "VideoTranscoderPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/VideoTranscoderPlugin"),
        .testTarget(
            name: "VideoTranscoderPluginTests",
            dependencies: ["VideoTranscoderPlugin"],
            path: "ios/Tests/VideoTranscoderPluginTests")
    ]
)