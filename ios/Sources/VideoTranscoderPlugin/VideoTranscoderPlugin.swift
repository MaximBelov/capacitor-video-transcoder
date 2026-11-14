import Capacitor
import Foundation
// A separate module under Swift Package Manager, the same module under CocoaPods.
#if canImport(VideoTranscoderCore)
import VideoTranscoderCore
#endif

@objc(VideoTranscoderPlugin)
public class VideoTranscoderPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "VideoTranscoderPlugin"
    public let jsName = "VideoTranscoder"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "transcode", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancel", returnType: CAPPluginReturnPromise)
    ]
    private let transcoder = Transcoder()

    @objc func transcode(_ call: CAPPluginCall) {
        let options: TranscodeOptions
        do {
            options = try TranscodeOptions.parse(VideoTranscoderPlugin.raw(call.options))
            // taken here, before the task, so that a second call made straight after this one is answered BUSY
            try transcoder.reserve()
        } catch {
            reject(call, error)
            return
        }
        Task {
            do {
                let outcome = try await transcoder.transcode(options, reserved: true) { [weak self] progress in
                    self?.notifyListeners("progress", data: ["progress": progress])
                }
                call.resolve(VideoTranscoderPlugin.result(outcome))
            } catch {
                reject(call, error)
            }
        }
    }

    @objc func cancel(_ call: CAPPluginCall) {
        transcoder.cancel()
        call.resolve()
    }

    static func raw(_ options: [AnyHashable: Any]?) -> [String: Any] {
        var raw: [String: Any] = [:]
        for (key, value) in options ?? [:] {
            if let key = key as? String {
                raw[key] = value
            }
        }
        return raw
    }

    static func result(_ outcome: TranscodeOutcome) -> [String: Any] {
        [
            "path": outcome.url.path,
            "uri": outcome.url.absoluteString,
            "width": outcome.width,
            "height": outcome.height,
            "durationMs": outcome.durationMs,
            "size": outcome.size
        ]
    }

    private func reject(_ call: CAPPluginCall, _ error: Error) {
        if let error = error as? TranscodeError {
            call.reject(error.message, error.code.rawValue)
        } else {
            call.reject(error.localizedDescription, TranscodeErrorCode.failed.rawValue)
        }
    }
}
