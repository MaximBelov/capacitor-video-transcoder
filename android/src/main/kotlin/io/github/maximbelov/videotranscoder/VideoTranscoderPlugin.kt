package io.github.maximbelov.videotranscoder

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONObject

@CapacitorPlugin(name = "VideoTranscoder")
class VideoTranscoderPlugin : Plugin() {
    private val transcoder by lazy { VideoTranscoder(context) }

    @PluginMethod
    fun transcode(call: PluginCall) {
        val options =
            try {
                TranscodeOptions.parse { key -> call.data.opt(key).takeUnless { it == JSONObject.NULL } }
            } catch (e: TranscodeException) {
                call.reject(e.message, e.code.name)
                return
            }
        transcoder.transcode(
            options,
            onProgress = { progress -> notifyListeners("progress", JSObject().put("progress", progress)) },
        ) { result ->
            result.fold(
                onSuccess = { outcome -> call.resolve(result(outcome)) },
                onFailure = { error ->
                    val code = (error as? TranscodeException)?.code ?: ErrorCode.FAILED
                    call.reject(error.message ?: code.name, code.name)
                },
            )
        }
    }

    @PluginMethod
    fun cancel(call: PluginCall) {
        transcoder.cancel()
        call.resolve()
    }

    private fun result(outcome: TranscodeOutcome) =
        JSObject()
            .put("path", outcome.file.absolutePath)
            .put("uri", TranscodeOptions.fileUrl(outcome.file))
            .put("width", outcome.width)
            .put("height", outcome.height)
            .put("durationMs", outcome.durationMs)
            .put("size", outcome.size)
}
