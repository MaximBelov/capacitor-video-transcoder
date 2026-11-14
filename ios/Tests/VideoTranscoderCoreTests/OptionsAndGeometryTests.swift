import CoreGraphics
import XCTest
@testable import VideoTranscoderCore

final class OptionsTests: XCTestCase {
    func testFillsTheDefaults() throws {
        let options = try TranscodeOptions.parse(["source": "/var/in.mov"])
        XCTAssertEqual(options.source.path, "/var/in.mov")
        XCTAssertNil(options.destination)
        XCTAssertEqual(options.maxSize, 1280)
        XCTAssertEqual(options.maxDurationMs, 30_000)
        XCTAssertEqual(options.videoBitrate, 1_800_000)
    }

    func testTakesFileURLsWithEscapes() throws {
        let options = try TranscodeOptions.parse([
            "source": "file:///var/mobile/My%20Video.mov",
            "destination": "file://localhost/tmp/out.mp4",
            "maxSize": 640,
            "maxDurationMs": 1500.0,
            "videoBitrate": NSNumber(value: 900_000)
        ])
        XCTAssertEqual(options.source.path, "/var/mobile/My Video.mov")
        XCTAssertEqual(options.destination?.path, "/tmp/out.mp4")
        XCTAssertEqual(options.maxSize, 640)
        XCTAssertEqual(options.maxDurationMs, 1500)
        XCTAssertEqual(options.videoBitrate, 900_000)
    }

    func testANullIsTheDefault() throws {
        let options = try TranscodeOptions.parse(["source": "/a.mov", "destination": NSNull(), "maxSize": NSNull()])
        XCTAssertNil(options.destination)
        XCTAssertEqual(options.maxSize, 1280)
    }

    func testRefusesWhatIsNotALocalFile() {
        for source in ["", "relative/in.mov", "content://media/external/video/1", "https://example.com/a.mp4", "file://", "/"] {
            XCTAssertThrowsError(try TranscodeOptions.parse(["source": source]), source) { error in
                XCTAssertEqual((error as? TranscodeError)?.code, .invalidArgument)
            }
        }
        XCTAssertThrowsError(try TranscodeOptions.parse([:]))
        XCTAssertThrowsError(try TranscodeOptions.parse(["source": 42]))
        XCTAssertThrowsError(try TranscodeOptions.parse(["source": "/a.mov", "destination": "out.mp4"]))
        XCTAssertThrowsError(try TranscodeOptions.parse(["source": "/a.mov", "destination": 1]))
    }

    func testRefusesNumbersOutOfRangeOrNotWhole() {
        let bad: [(String, Any)] = [
            ("maxSize", 15), ("maxSize", 640.5), ("maxSize", "640"), ("maxSize", true), ("maxSize", Double.nan),
            ("maxDurationMs", 0), ("maxDurationMs", -1), ("videoBitrate", 0), ("videoBitrate", 1e12)
        ]
        for (key, value) in bad {
            XCTAssertThrowsError(try TranscodeOptions.parse(["source": "/a.mov", key: value]), "\(key)=\(value)") { error in
                XCTAssertEqual((error as? TranscodeError)?.code, .invalidArgument)
                XCTAssertTrue((error as? TranscodeError)?.message.contains(key) ?? false)
            }
        }
        XCTAssertEqual(try TranscodeOptions.parse(["source": "/a.mov", "maxSize": 16]).maxSize, 16)
    }
}

final class GeometryTests: XCTestCase {
    func testScalesTheLongerSideDownToMaxSize() {
        XCTAssertEqual(Geometry.outputSize(width: 1920, height: 1080, maxSize: 1280), VideoSize(width: 1280, height: 720))
        XCTAssertEqual(Geometry.outputSize(width: 1080, height: 1920, maxSize: 1280), VideoSize(width: 720, height: 1280))
        XCTAssertEqual(Geometry.outputSize(width: 3840, height: 2160, maxSize: 1280), VideoSize(width: 1280, height: 720))
        XCTAssertEqual(Geometry.outputSize(width: 1440, height: 1080, maxSize: 1280), VideoSize(width: 1280, height: 960))
    }

    func testNeverScalesUpAndKeepsSidesEven() {
        XCTAssertEqual(Geometry.outputSize(width: 640, height: 360, maxSize: 1280), VideoSize(width: 640, height: 360))
        XCTAssertEqual(Geometry.outputSize(width: 321, height: 241, maxSize: 1280), VideoSize(width: 320, height: 240))
        // an odd maxSize is not exceeded by rounding
        XCTAssertEqual(Geometry.outputSize(width: 1920, height: 1080, maxSize: 1281), VideoSize(width: 1280, height: 720))
        // a sliver keeps at least two pixels
        XCTAssertEqual(Geometry.outputSize(width: 4000, height: 3, maxSize: 1280), VideoSize(width: 1280, height: 2))
    }

    func testReadsTheRotationOfATrackTransform() {
        XCTAssertEqual(Geometry.rotationDegrees(of: .identity), 0)
        XCTAssertEqual(Geometry.rotationDegrees(of: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)), 90)
        XCTAssertEqual(Geometry.rotationDegrees(of: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), 180)
        XCTAssertEqual(Geometry.rotationDegrees(of: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), 270)
        XCTAssertEqual(Geometry.displayedSize(VideoSize(width: 1280, height: 720), rotationDegrees: 90), VideoSize(width: 720, height: 1280))
        XCTAssertEqual(Geometry.displayedSize(VideoSize(width: 1280, height: 720), rotationDegrees: 180), VideoSize(width: 1280, height: 720))
    }

    func testAudioFollowsTheSourceChannels() {
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 1, sourceSampleRate: 44_100).channels, 1)
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 2, sourceSampleRate: 48_000).channels, 2)
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 6, sourceSampleRate: 48_000).channels, 2)
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 2, sourceSampleRate: 16_000).sampleRate, 16_000)
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 2, sourceSampleRate: 44_000).sampleRate, 44_100)
        XCTAssertEqual(Geometry.aacFormat(sourceChannels: 2, sourceSampleRate: 96_000).sampleRate, 48_000)
    }

    func testProgressStaysBelowOneUntilTheEnd() {
        XCTAssertEqual(Geometry.progress(seconds: 0, of: 10), 0)
        XCTAssertEqual(Geometry.progress(seconds: 5, of: 10), 0.5)
        XCTAssertEqual(Geometry.progress(seconds: 10, of: 10), 0.99)
        XCTAssertEqual(Geometry.progress(seconds: -1, of: 10), 0)
        XCTAssertEqual(Geometry.progress(seconds: 1, of: 0), 0)
        XCTAssertEqual(Geometry.progress(seconds: .nan, of: 10), 0)
    }
}

final class PumpsTests: XCTestCase {
    func testWaitsForEveryTrackThatFinishes() async {
        let pumps = Pumps(count: 2)
        let ended = Flag()
        let waiting = Task {
            await pumps.wait()
            ended.set()
        }
        pumps.leave(finished: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(ended.value, "one of two tracks is not the end")
        pumps.leave(finished: true)
        await waiting.value
        XCTAssertTrue(ended.value)
    }

    func testATrackThatStopsEarlyEndsTheWaitAtOnce() async {
        // the other track never reports: the writer holds it back behind the stopped one
        let pumps = Pumps(count: 2)
        pumps.leave(finished: false)
        await pumps.wait()
        pumps.leave(finished: true) // a late report is ignored
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() {
        lock.lock()
        flag = true
        lock.unlock()
    }
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}
