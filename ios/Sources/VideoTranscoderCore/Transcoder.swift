import AVFoundation
import Foundation

/// What a finished transcode wrote.
public struct TranscodeOutcome: Equatable {
    public let url: URL
    /// The size a player shows, upright.
    public let width: Int
    public let height: Int
    public let durationMs: Int
    public let size: Int

    public init(url: URL, width: Int, height: Int, durationMs: Int, size: Int) {
        self.url = url
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.size = size
    }
}

/// Transcodes a video into an MP4 a web browser plays, with AVAssetReader and AVAssetWriter: H.264 High, 8-bit 4:2:0 tagged
/// BT.709 (an HDR source is converted by the decoder, which is asked for BT.709), AAC audio (an AAC source is copied, anything
/// else encoded), the longer side at most `maxSize`, cut at `maxDurationMs`, `moov` before `mdat`, and the source's rotation kept as
/// the track transform. One transcode at a time.
public final class Transcoder: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var cancelled = false
    private var reader: AVAssetReader?

    public init() {}

    /// Stops the running transcode, which then throws `CANCELLED`. Does nothing when none is running.
    public func cancel() {
        lock.lock()
        let reader = running ? self.reader : nil
        if running {
            cancelled = true
        }
        lock.unlock()
        reader?.cancelReading()
    }

    /// Takes the one slot there is, or throws `BUSY`. `transcode` takes it on its own; a caller that has to answer `BUSY` before it
    /// can start a task (the bridge) takes it first and passes `reserved: true`.
    public func reserve() throws {
        lock.lock()
        defer { lock.unlock() }
        if running {
            throw TranscodeError(.busy, "another transcode is still running")
        }
        running = true
        cancelled = false
    }

    public func transcode(
        _ options: TranscodeOptions,
        reserved: Bool = false,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> TranscodeOutcome {
        if !reserved {
            try reserve()
        }
        defer { release() }

        let output = options.destination ?? Transcoder.newDestination()
        do {
            return try await run(options, output: output, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: output)
            if isCancelled {
                throw TranscodeError(.cancelled, "the transcode was cancelled")
            }
            if let error = error as? TranscodeError {
                throw error
            }
            throw TranscodeError(.failed, error.localizedDescription)
        }
    }

    private func release() {
        lock.lock()
        running = false
        reader = nil
        lock.unlock()
    }

    /// Makes `reader` the one `cancel()` stops, and says whether a cancel already came.
    private func attach(_ reader: AVAssetReader) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.reader = reader
        return cancelled
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    static func newDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("video-transcoder", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".mp4")
    }

    static let bt709: [String: Any] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    static let aacSubtypes: Set<AudioFormatID> = [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2]

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func run(_ options: TranscodeOptions, output: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> TranscodeOutcome {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: options.source.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: options.source.path) else {
            throw TranscodeError(.notFound, "there is no readable file at \(options.source.path)")
        }

        let asset = AVURLAsset(url: options.source)
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let duration: CMTime
        let naturalSize: CGSize
        let transform: CGAffineTransform
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw TranscodeError(.noVideo, "\(options.source.lastPathComponent) has no video track")
            }
            videoTrack = track
            audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            duration = try await asset.load(.duration)
            naturalSize = try await videoTrack.load(.naturalSize)
            transform = try await videoTrack.load(.preferredTransform)
        } catch let error as TranscodeError {
            throw error
        } catch {
            throw TranscodeError(.noVideo, "\(options.source.lastPathComponent) is not a video this device reads: \(error.localizedDescription)")
        }

        let limit = CMTime(value: CMTimeValue(options.maxDurationMs), timescale: 1000)
        let clip = duration.isNumeric && duration > .zero ? CMTimeMinimum(duration, limit) : limit
        let size = Geometry.outputSize(width: Int(naturalSize.width), height: Int(naturalSize.height), maxSize: options.maxSize)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: clip)
        // 8-bit 4:2:0 out of the decoder, converted to BT.709: this is where an HDR (10-bit HLG or PQ) source is tone-mapped.
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            AVVideoColorPropertiesKey: Transcoder.bt709
        ])
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else {
            throw TranscodeError(.failed, "the video track cannot be decoded")
        }
        reader.add(videoOut)

        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true // moov before mdat
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoColorPropertiesKey: Transcoder.bt709,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAverageBitRateKey: options.videoBitrate
            ]
        ])
        // The rotation stays metadata, as the phone wrote it: the frames are stored as recorded and the player turns them upright.
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoIn) else {
            throw TranscodeError(.failed, "the H.264 encoder does not take \(size.width)x\(size.height)")
        }
        writer.add(videoIn)

        var audio: (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput)?
        if let audioTrack {
            audio = try await audioPair(for: audioTrack)
            if let audio, reader.canAdd(audio.output), writer.canAdd(audio.input) {
                reader.add(audio.output)
                writer.add(audio.input)
            } else {
                throw TranscodeError(.failed, "the audio track cannot be converted to AAC")
            }
        }

        if attach(reader) {
            throw TranscodeError(.cancelled, "the transcode was cancelled")
        }

        guard reader.startReading() else {
            throw TranscodeError(.failed, "the video cannot be read: \(reader.error?.localizedDescription ?? "unknown error")")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw TranscodeError(.failed, "the MP4 cannot be written: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        writer.startSession(atSourceTime: .zero)

        let pumps = Pumps(count: audio == nil ? 1 : 2)
        let clipSeconds = clip.seconds
        let reported = Reported()
        pump(videoIn, from: videoOut, label: "video", pumps: pumps, writer: writer) { time in
            let value = Geometry.progress(seconds: time.seconds, of: clipSeconds)
            if reported.advance(to: value) {
                progress(value)
            }
        }
        if let audio {
            pump(audio.input, from: audio.output, label: "audio", pumps: pumps, writer: writer) { _ in }
        }
        await pumps.wait()

        if isCancelled {
            writer.cancelWriting()
            throw TranscodeError(.cancelled, "the transcode was cancelled")
        }
        if reader.status == .failed || writer.status == .failed {
            let reason = (writer.error ?? reader.error)?.localizedDescription ?? "unknown error"
            writer.cancelWriting()
            throw TranscodeError(.failed, reason)
        }
        writer.endSession(atSourceTime: clip)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw TranscodeError(.failed, "the MP4 was not finished: \(writer.error?.localizedDescription ?? "unknown error")")
        }

        let written = AVURLAsset(url: output)
        let writtenDuration = (try? await written.load(.duration)) ?? clip
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
        let shown = Geometry.displayedSize(size, rotationDegrees: Geometry.rotationDegrees(of: transform))
        progress(1)
        return TranscodeOutcome(
            url: output,
            width: shown.width,
            height: shown.height,
            durationMs: Int((writtenDuration.seconds * 1000).rounded()),
            size: fileSize
        )
    }

    /// The reader output and writer input for an audio track: AAC is passed through untouched, anything else decoded to PCM and
    /// encoded to AAC with the source's channel count (more than two are mixed down to stereo).
    private func audioPair(for track: AVAssetTrack) async throws -> (output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        let descriptions = try await track.load(.formatDescriptions)
        let description = descriptions.first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        if let description, let basic, Transcoder.aacSubtypes.contains(basic.mFormatID) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: description)
            input.expectsMediaDataInRealTime = false
            return (output, input)
        }
        let format = Geometry.aacFormat(
            sourceChannels: Int(basic?.mChannelsPerFrame ?? 2),
            sourceSampleRate: basic?.mSampleRate ?? 44_100
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: format.channels,
            AVSampleRateKey: format.sampleRate
        ])
        input.expectsMediaDataInRealTime = false
        return (output, input)
    }

    /// Copies one track from the reader to the writer on its own queue, and tells `pumps` when the track ends, the transcode is
    /// cancelled, or the writer stops taking samples.
    private func pump(
        _ input: AVAssetWriterInput,
        from output: AVAssetReaderTrackOutput,
        label: String,
        pumps: Pumps,
        writer: AVAssetWriter,
        onSample: @escaping (CMTime) -> Void
    ) {
        var left = false
        func leave(finished: Bool) {
            guard !left else { return }
            left = true
            if finished {
                input.markAsFinished()
            }
            pumps.leave(finished: finished)
        }
        input.requestMediaDataWhenReady(on: DispatchQueue(label: "video-transcoder.\(label)")) { [weak self] in
            while input.isReadyForMoreMediaData, !left {
                if self?.isCancelled ?? true || writer.status != .writing {
                    leave(finished: false)
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    leave(finished: !(self?.isCancelled ?? true) && writer.status == .writing)
                    return
                }
                onSample(CMSampleBufferGetPresentationTimeStamp(sample))
                if !input.append(sample) {
                    leave(finished: false)
                    return
                }
            }
        }
    }
}

/// Waits for the track pumps. Every one has to finish for the file to be complete, but one that stops early (a cancel, a failed
/// append) ends the wait at once: the other may never be asked for data again, because the writer holds it back until the stopped
/// track catches up. Waiting for both is how a cancel hung on an iPhone, with the audio pump parked behind the video.
final class Pumps: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var over = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(count: Int) {
        remaining = count
    }

    func leave(finished: Bool) {
        lock.lock()
        remaining -= 1
        let end = !over && (!finished || remaining == 0)
        if end {
            over = true
        }
        let resume = end ? waiter : nil
        if end {
            waiter = nil
        }
        lock.unlock()
        resume?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if !park(continuation) {
                continuation.resume()
            }
        }
    }

    /// Keeps the continuation to resume later, or says the wait is already over.
    private func park(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if over {
            return false
        }
        waiter = continuation
        return true
    }
}

/// The last progress value reported, so that only a value at least a percent further is reported again.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0

    func advance(to value: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value >= last + 0.01 else {
            return false
        }
        last = value
        return true
    }
}
