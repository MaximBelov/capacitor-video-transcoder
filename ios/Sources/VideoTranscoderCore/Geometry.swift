import CoreGraphics
import Foundation

public struct VideoSize: Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The arithmetic of the output: its size, its rotation, its audio format. Pure, so it is tested without a video.
public enum Geometry {
    /// The size that fits a video into `maxSize` on its longer side, keeping the aspect ratio and never scaling up. Both sides are
    /// rounded down to an even number (H.264 4:2:0 halves them for the chroma planes), and are at least 2. Integer arithmetic, so
    /// 1920x1080 into 1280 is exactly 1280x720 and not 1280x718 from a 719.999 rounded down.
    public static func outputSize(width: Int, height: Int, maxSize: Int) -> VideoSize {
        let w = Int64(max(abs(width), 1))
        let h = Int64(max(abs(height), 1))
        let longer = max(w, h)
        let limit = Int64(max(maxSize, 2))
        func fit(_ side: Int64) -> Int {
            let scaled = longer > limit ? side * limit / longer : side
            return Int(max(2, scaled / 2 * 2))
        }
        return VideoSize(width: fit(w), height: fit(h))
    }

    /// The clockwise rotation a track transform applies, in degrees: 0, 90, 180 or 270.
    public static func rotationDegrees(of transform: CGAffineTransform) -> Int {
        let degrees = Int((atan2(Double(transform.b), Double(transform.a)) * 180 / .pi).rounded())
        return ((degrees % 360) + 360) % 360 / 90 * 90
    }

    /// A stored size as a player shows it, with the track's rotation applied.
    public static func displayedSize(_ size: VideoSize, rotationDegrees: Int) -> VideoSize {
        rotationDegrees % 180 == 0 ? size : VideoSize(width: size.height, height: size.width)
    }

    /// The sample rates the AAC encoder takes.
    static let aacSampleRates: [Double] = [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]

    /// The AAC format an audio track that is not AAC is encoded to: mono stays mono, stereo stays stereo, more channels are mixed
    /// down to stereo; the sample rate is the source's when AAC has it, else the next one up, at most 48 kHz. The bitrate is left
    /// to the encoder, which picks one that suits the sample rate: a fixed 128 kbit/s is refused at 16 kHz ("Cannot Encode Media").
    public static func aacFormat(sourceChannels: Int, sourceSampleRate: Double) -> (channels: Int, sampleRate: Double) {
        let channels = sourceChannels <= 1 ? 1 : 2
        let sampleRate = aacSampleRates.first { $0 >= sourceSampleRate.rounded() } ?? 48_000
        return (channels, sampleRate)
    }

    /// Progress from 0 to 1 for a position in a clip, held below 1 until the file is finished.
    public static func progress(seconds: Double, of duration: Double) -> Double {
        guard duration > 0, seconds.isFinite else {
            return 0
        }
        return min(max(seconds / duration, 0), 0.99)
    }
}
