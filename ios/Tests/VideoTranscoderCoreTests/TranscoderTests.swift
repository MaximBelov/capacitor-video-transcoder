import AVFoundation
import XCTest
@testable import VideoTranscoderCore

/// End to end: the fixtures in test/fixtures transcoded with AVFoundation, and the output read back. On a Mac with `swift test`
/// this is the same AVAssetReader/AVAssetWriter path the phone takes, with the Mac's encoder instead of the phone's.
final class TranscoderTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VideoTranscoderCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // the repository
        .appendingPathComponent("test/fixtures")

    var outputs: URL!

    override func setUpWithError() throws {
        outputs = FileManager.default.temporaryDirectory.appendingPathComponent("video-transcoder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: outputs)
    }

    func fixture(_ name: String) -> URL { TranscoderTests.fixtures.appendingPathComponent(name) }

    func testRotatedVideoWithPCMAudio() async throws {
        let out = outputs.appendingPathComponent("rotated.mp4")
        let progress = Recorder()
        let outcome = try await Transcoder().transcode(
            TranscodeOptions(source: fixture("rotated-pcm.mov"), destination: out),
            progress: { progress.add($0) }
        )
        XCTAssertEqual(outcome.url, out)
        // stored 320x240, shown upright as 240x320
        XCTAssertEqual(outcome.width, 240)
        XCTAssertEqual(outcome.height, 320)
        XCTAssertEqual(Double(outcome.durationMs), 2000, accuracy: 100)
        XCTAssertGreaterThan(outcome.size, 0)

        let facts = try await Facts.read(out)
        XCTAssertEqual(facts.videoCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(facts.avcProfile, 100, "H.264 High")
        XCTAssertEqual(facts.storedSize, CGSize(width: 320, height: 240))
        // the rotation is carried over as the track transform, unchanged
        let source = try await Facts.read(fixture("rotated-pcm.mov"))
        XCTAssertNotEqual(Geometry.rotationDegrees(of: source.transform), 0)
        XCTAssertEqual(Geometry.rotationDegrees(of: facts.transform), Geometry.rotationDegrees(of: source.transform))
        XCTAssertEqual(facts.primaries, kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(facts.transfer, kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        XCTAssertEqual(facts.matrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
        XCTAssertEqual(facts.audioFormat, kAudioFormatMPEG4AAC)
        XCTAssertEqual(facts.audioChannels, 2)
        XCTAssertEqual(facts.audioSampleRate, 16_000)
        XCTAssertEqual(facts.topLevelAtoms.filter { $0 == "moov" || $0 == "mdat" }, ["moov", "mdat"], "faststart")

        let values = progress.values
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted(), "progress only grows")
        XCTAssertGreaterThan(values.count, 2)
    }

    func testHDRIsToneMappedAndAACIsCopied() async throws {
        let out = outputs.appendingPathComponent("hdr.mp4")
        let outcome = try await Transcoder().transcode(TranscodeOptions(source: fixture("hdr-hlg.mov"), destination: out))
        XCTAssertEqual(outcome.width, 256)
        XCTAssertEqual(outcome.height, 144)

        let facts = try await Facts.read(out)
        XCTAssertEqual(facts.videoCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(facts.primaries, kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        XCTAssertEqual(facts.transfer, kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        XCTAssertEqual(facts.audioFormat, kAudioFormatMPEG4AAC)
        XCTAssertEqual(facts.audioChannels, 1)
        XCTAssertEqual(facts.audioSampleRate, 44_100)
    }

    func testScalesDownCutsAndAddsNoAudio() async throws {
        let out = outputs.appendingPathComponent("nested/dir/silent.mp4")
        let outcome = try await Transcoder().transcode(TranscodeOptions(
            source: fixture("long-silent.mp4"), destination: out, maxSize: 320, maxDurationMs: 1500, videoBitrate: 200_000
        ))
        XCTAssertEqual(outcome.width, 320)
        XCTAssertEqual(outcome.height, 180)
        XCTAssertEqual(Double(outcome.durationMs), 1500, accuracy: 70)

        let facts = try await Facts.read(out)
        XCTAssertEqual(facts.storedSize, CGSize(width: 320, height: 180))
        XCTAssertNil(facts.audioFormat)
    }

    func testReplacesAFileAtTheDestinationAndDefaultsToTheTemporaryDirectory() async throws {
        let out = outputs.appendingPathComponent("taken.mp4")
        try Data("not a video".utf8).write(to: out)
        _ = try await Transcoder().transcode(TranscodeOptions(source: fixture("hdr-hlg.mov"), destination: out))
        let replaced = try await Facts.read(out)
        XCTAssertEqual(replaced.videoCodec, kCMVideoCodecType_H264)

        let outcome = try await Transcoder().transcode(TranscodeOptions(source: fixture("hdr-hlg.mov")))
        defer { try? FileManager.default.removeItem(at: outcome.url) }
        XCTAssertTrue(outcome.url.path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path)
            || outcome.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(outcome.url.pathExtension, "mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.url.path))
    }

    func testNotFoundAndNoVideo() async throws {
        await assertFails(.notFound, TranscodeOptions(source: outputs.appendingPathComponent("missing.mov")))
        await assertFails(.notFound, TranscodeOptions(source: outputs))
        let text = outputs.appendingPathComponent("text.mov")
        try Data("not a video".utf8).write(to: text)
        let out = outputs.appendingPathComponent("never.mp4")
        await assertFails(.noVideo, TranscodeOptions(source: text, destination: out))
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testOneAtATimeAndCancel() async throws {
        let transcoder = Transcoder()
        let out = outputs.appendingPathComponent("cancelled.mp4")
        let started = expectation(description: "progress")
        started.assertForOverFulfill = false
        let first = Task {
            try await transcoder.transcode(TranscodeOptions(source: fixture("long-silent.mp4"), destination: out)) { _ in
                started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 30)
        await assertFails(.busy, TranscodeOptions(source: fixture("hdr-hlg.mov")), with: transcoder)
        transcoder.cancel()
        do {
            _ = try await first.value
            // a fast machine can finish the clip before the cancel lands; then there is nothing to check
        } catch {
            XCTAssertEqual((error as? TranscodeError)?.code, .cancelled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "a cancelled transcode leaves no file")
        }
        // and the transcoder is free again
        _ = try await transcoder.transcode(TranscodeOptions(source: fixture("hdr-hlg.mov"), destination: out))
        transcoder.cancel() // with nothing running, nothing happens
    }

    func assertFails(
        _ code: TranscodeErrorCode,
        _ options: TranscodeOptions,
        with transcoder: Transcoder = Transcoder(),
        line: UInt = #line
    ) async {
        do {
            _ = try await transcoder.transcode(options)
            XCTFail("expected \(code.rawValue)", line: line)
        } catch {
            XCTAssertEqual((error as? TranscodeError)?.code, code, "\(error)", line: line)
        }
    }
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Double] = []
    func add(_ value: Double) {
        lock.lock()
        list.append(value)
        lock.unlock()
    }
    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }
}

/// What a written MP4 says about itself, read with AVFoundation and from its top-level boxes.
struct Facts {
    var videoCodec: FourCharCode?
    var avcProfile: UInt8?
    var storedSize = CGSize.zero
    var transform = CGAffineTransform.identity
    var primaries: String?
    var transfer: String?
    var matrix: String?
    var audioFormat: AudioFormatID?
    var audioChannels: UInt32?
    var audioSampleRate: Float64?
    var topLevelAtoms: [String] = []

    static func read(_ url: URL) async throws -> Facts {
        var facts = Facts()
        let asset = AVURLAsset(url: url)
        if let video = try await asset.loadTracks(withMediaType: .video).first {
            facts.storedSize = try await video.load(.naturalSize)
            facts.transform = try await video.load(.preferredTransform)
            if let description = try await video.load(.formatDescriptions).first {
                facts.videoCodec = CMFormatDescriptionGetMediaSubType(description)
                let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]
                facts.primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                facts.transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                facts.matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
                let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any]
                if let avcC = atoms?["avcC"] as? Data, avcC.count > 1 {
                    facts.avcProfile = avcC[avcC.startIndex + 1]
                }
            }
        }
        if let audio = try await asset.loadTracks(withMediaType: .audio).first,
           let description = try await audio.load(.formatDescriptions).first,
           let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            facts.audioFormat = basic.mFormatID
            facts.audioChannels = basic.mChannelsPerFrame
            facts.audioSampleRate = basic.mSampleRate
        }
        facts.topLevelAtoms = try topLevelAtoms(url)
        return facts
    }

    static func topLevelAtoms(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var atoms: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            var size = data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt64($1) }
            let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
            if size == 1, offset + 16 <= data.count {
                size = data[offset + 8..<offset + 16].reduce(0) { $0 << 8 | UInt64($1) }
            } else if size == 0 {
                size = UInt64(data.count - offset)
            }
            atoms.append(type)
            guard size >= 8 else { break }
            offset += Int(size)
        }
        return atoms
    }
}
