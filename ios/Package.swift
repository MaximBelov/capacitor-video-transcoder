// swift-tools-version: 5.9
import PackageDescription

// The transcoder without the Capacitor bridge, so that `swift test --package-path ios` runs its tests on a Mac: no simulator, no
// phone. AVAssetReader and AVAssetWriter are the same on macOS, so the end-to-end tests transcode real files here. The plugin
// itself is the package at the root of the repository, which builds these same sources.
let package = Package(
    name: "VideoTranscoderCore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "VideoTranscoderCore", targets: ["VideoTranscoderCore"])
    ],
    targets: [
        .target(
            name: "VideoTranscoderCore",
            path: "Sources/VideoTranscoderCore"),
        .testTarget(
            name: "VideoTranscoderCoreTests",
            dependencies: ["VideoTranscoderCore"],
            path: "Tests/VideoTranscoderCoreTests")
    ]
)
