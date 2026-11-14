import XCTest
@testable import VideoTranscoderPlugin
import VideoTranscoderCore

/// The bridge side of the plugin: its name and methods, and how a call's options and a finished transcode cross the bridge. The
/// transcoding itself is tested in VideoTranscoderCoreTests, which also run on a Mac without a simulator.
final class VideoTranscoderPluginTests: XCTestCase {
    func testRegistersTheMethodsOfTheTypeScriptAPI() {
        let plugin = VideoTranscoderPlugin()
        XCTAssertEqual(plugin.jsName, "VideoTranscoder")
        XCTAssertEqual(plugin.pluginMethods.map(\.name), ["transcode", "cancel"])
    }

    func testKeepsTheStringKeysOfTheCallOptions() {
        let raw = VideoTranscoderPlugin.raw(["source": "/a.mov", "maxSize": 640, 1: "dropped"])
        XCTAssertEqual(raw.count, 2)
        XCTAssertEqual(try TranscodeOptions.parse(raw).maxSize, 640)
    }

    func testResultCarriesEveryFieldOfTheTypeScriptResult() {
        let url = URL(fileURLWithPath: "/tmp/out put.mp4")
        let result = VideoTranscoderPlugin.result(
            TranscodeOutcome(url: url, width: 720, height: 1280, durationMs: 3000, size: 12345)
        )
        XCTAssertEqual(result["path"] as? String, "/tmp/out put.mp4")
        XCTAssertEqual(result["uri"] as? String, "file:///tmp/out%20put.mp4")
        XCTAssertEqual(result["width"] as? Int, 720)
        XCTAssertEqual(result["height"] as? Int, 1280)
        XCTAssertEqual(result["durationMs"] as? Int, 3000)
        XCTAssertEqual(result["size"] as? Int, 12345)
    }
}
