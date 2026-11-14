import CoreFoundation
import Foundation

/// The `code` a call is rejected with. The raw values are the ones `src/definitions.ts` documents.
public enum TranscodeErrorCode: String {
    case invalidArgument = "INVALID_ARGUMENT"
    case notFound = "NOT_FOUND"
    case noVideo = "NO_VIDEO"
    case busy = "BUSY"
    case cancelled = "CANCELLED"
    case failed = "FAILED"
}

public struct TranscodeError: Error, Equatable, CustomStringConvertible {
    public let code: TranscodeErrorCode
    public let message: String

    public init(_ code: TranscodeErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}

/// What a `transcode` call asked for, checked and with the defaults filled in.
public struct TranscodeOptions: Equatable {
    public static let defaultMaxSize = 1280
    public static let defaultMaxDurationMs = 30_000
    public static let defaultVideoBitrate = 1_800_000
    public static let minimumMaxSize = 16

    public let source: URL
    /// `nil` when the call named none: a new file in the temporary directory is used.
    public let destination: URL?
    public let maxSize: Int
    public let maxDurationMs: Int
    public let videoBitrate: Int

    public init(
        source: URL,
        destination: URL? = nil,
        maxSize: Int = TranscodeOptions.defaultMaxSize,
        maxDurationMs: Int = TranscodeOptions.defaultMaxDurationMs,
        videoBitrate: Int = TranscodeOptions.defaultVideoBitrate
    ) {
        self.source = source
        self.destination = destination
        self.maxSize = maxSize
        self.maxDurationMs = maxDurationMs
        self.videoBitrate = videoBitrate
    }

    /// The options of a call as the bridge hands them over. Anything wrong is an `INVALID_ARGUMENT` that says what.
    public static func parse(_ raw: [String: Any]) throws -> TranscodeOptions {
        guard let source = raw["source"] as? String, !source.isEmpty else {
            throw TranscodeError(.invalidArgument, "source is required: an absolute path or a file:// URL")
        }
        var destination: URL?
        if let value = raw["destination"], !(value is NSNull) {
            guard let text = value as? String else {
                throw TranscodeError(.invalidArgument, "destination must be a string")
            }
            destination = try fileURL(text, name: "destination")
        }
        return TranscodeOptions(
            source: try fileURL(source, name: "source"),
            destination: destination,
            maxSize: try wholeNumber(raw["maxSize"], name: "maxSize", minimum: minimumMaxSize, fallback: defaultMaxSize),
            maxDurationMs: try wholeNumber(raw["maxDurationMs"], name: "maxDurationMs", minimum: 1, fallback: defaultMaxDurationMs),
            videoBitrate: try wholeNumber(raw["videoBitrate"], name: "videoBitrate", minimum: 1, fallback: defaultVideoBitrate)
        )
    }

    /// An absolute path or a `file://` URL as a file URL. Anything else (a relative path, `content://`, `http://`) is refused.
    public static func fileURL(_ value: String, name: String) throws -> URL {
        var path = value
        if value.hasPrefix("file://") {
            path = String(value.dropFirst("file://".count))
            if path.hasPrefix("localhost/") {
                path = String(path.dropFirst("localhost".count))
            }
            path = path.removingPercentEncoding ?? path
        }
        guard path.hasPrefix("/"), path.count > 1 else {
            throw TranscodeError(.invalidArgument, "\(name) must be an absolute path or a file:// URL, not \(value)")
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static func wholeNumber(_ value: Any?, name: String, minimum: Int, fallback: Int) throws -> Int {
        guard let value, !(value is NSNull) else {
            return fallback
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw TranscodeError(.invalidArgument, "\(name) must be a number")
        }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double <= Double(Int32.max) else {
            throw TranscodeError(.invalidArgument, "\(name) must be a whole number, not \(number)")
        }
        guard Int(double) >= minimum else {
            throw TranscodeError(.invalidArgument, "\(name) must be at least \(minimum), not \(number)")
        }
        return Int(double)
    }
}
