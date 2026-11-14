package io.github.maximbelov.videotranscoder

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** What a finished transcode wrote. [width] and [height] are the size a player shows, upright. */
data class TranscodeOutcome(val file: File, val width: Int, val height: Int, val durationMs: Long, val size: Long)

/**
 * Transcodes a video into an MP4 a web browser plays, with Media3 Transformer: H.264 (High where the encoder has it, which
 * Media3 picks on its own), 8-bit 4:2:0 BT.709 with HDR tone-mapped to SDR in OpenGL, AAC (an AAC source is copied, anything else
 * encoded), the longer side at most `maxSize`, cut at `maxDurationMs`, `moov` before `mdat`, and the rotation kept as metadata.
 * One transcode at a time; Transformer runs on the main looper.
 */
class VideoTranscoder(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)

    @Volatile private var cancelRequested = false

    /** Touched on the main thread only. */
    private var job: Job? = null

    private inner class Job(
        val transformer: Transformer,
        val output: File,
        val onProgress: (Double) -> Unit,
        val onDone: (Result<TranscodeOutcome>) -> Unit,
    ) {
        var finished = false
        var reported = -1.0
        val holder = ProgressHolder()
        val poll =
            object : Runnable {
                override fun run() {
                    if (finished) return
                    if (transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                        val value = Geometry.progress(holder.progress)
                        if (value >= reported + 0.01) {
                            reported = value
                            onProgress(value)
                        }
                    }
                    main.postDelayed(this, PROGRESS_INTERVAL_MS)
                }
            }

        fun finish(result: Result<TranscodeOutcome>) {
            if (finished) return
            finished = true
            main.removeCallbacks(poll)
            if (result.isFailure) output.delete()
            job = null
            running.set(false)
            onDone(result)
        }
    }

    /** Starts a transcode; [onDone] is called once, on the main thread or on the calling one. */
    fun transcode(options: TranscodeOptions, onProgress: (Double) -> Unit, onDone: (Result<TranscodeOutcome>) -> Unit) {
        if (!running.compareAndSet(false, true)) {
            onDone(Result.failure(TranscodeException(ErrorCode.BUSY, "another transcode is still running")))
            return
        }
        cancelRequested = false
        val output: File
        val uri: Uri
        val target: Pair<Int, Int>
        val hasAudio: Boolean
        try {
            uri = openable(options.source)
            val source = probe(uri)
            hasAudio = source.hasAudio
            val shown = Geometry.displayedSize(source.width, source.height, source.rotation)
            // Transformer turns the frames upright before the effects, so the size is fitted to the size as shown; it then
            // encodes them in the orientation the encoder prefers and writes the rotation back as metadata.
            target = Geometry.outputSize(shown.first, shown.second, options.maxSize)
            output =
                options.destination?.let { File(it) }
                    ?: File(File(context.cacheDir, "video-transcoder"), "${UUID.randomUUID()}.mp4")
            output.parentFile?.mkdirs()
            if (output.exists() && !output.delete()) {
                throw TranscodeException(ErrorCode.FAILED, "the file at ${output.path} cannot be replaced")
            }
        } catch (e: TranscodeException) {
            running.set(false)
            onDone(Result.failure(e))
            return
        }

        val item =
            MediaItem.Builder()
                .setUri(uri)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder().setEndPositionMs(options.maxDurationMs).build(),
                )
                .build()
        val edited =
            EditedMediaItem.Builder(item)
                .setEffects(
                    Effects(
                        listOf(),
                        listOf(Presentation.createForWidthAndHeight(target.first, target.second, Presentation.LAYOUT_SCALE_TO_FIT)),
                    ),
                )
                .build()
        // A sequence that has audio makes an audio track even when the source has none (silence, measured on a Pixel 10a), so a
        // video without sound gets a video-only sequence.
        val sequence =
            if (hasAudio) EditedMediaItemSequence.withAudioAndVideoFrom(listOf(edited)) else EditedMediaItemSequence.withVideoFrom(listOf(edited))
        val composition =
            Composition.Builder(sequence)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

        main.post {
            if (cancelRequested) {
                output.delete()
                running.set(false)
                onDone(Result.failure(cancelled()))
                return@post
            }
            var current: Job? = null
            val transformer =
                Transformer.Builder(context)
                    .setEncoderFactory(
                        DefaultEncoderFactory.Builder(context)
                            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(options.videoBitrate).build())
                            .build(),
                    )
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setMuxerFactory(InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(true))
                    .addListener(
                        object : Transformer.Listener {
                            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                                val active = current ?: return
                                val outcome = runCatching { describe(output) }
                                if (outcome.isSuccess) active.onProgress(1.0)
                                active.finish(outcome)
                            }

                            override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                                current?.finish(
                                    Result.failure(
                                        TranscodeException(ErrorCode.FAILED, "${exception.errorCodeName}: ${exception.message}"),
                                    ),
                                )
                            }
                        },
                    )
                    .build()
            current = Job(transformer, output, onProgress, onDone)
            job = current
            try {
                transformer.start(composition, output.path)
                main.post(current.poll)
            } catch (e: RuntimeException) {
                current.finish(Result.failure(TranscodeException(ErrorCode.FAILED, e.message ?: e.toString())))
            }
        }
    }

    /** Stops the running transcode, which then fails with `CANCELLED`. Does nothing when none is running. */
    fun cancel() {
        if (!running.get()) return
        cancelRequested = true
        main.post {
            val current = job ?: return@post
            current.transformer.cancel()
            current.finish(Result.failure(cancelled()))
        }
    }

    private fun cancelled() = TranscodeException(ErrorCode.CANCELLED, "the transcode was cancelled")

    /** The source as a URI Media3 reads, once it is known to open. */
    private fun openable(source: SourceLocation): Uri =
        when (source) {
            is SourceLocation.File -> {
                val file = File(source.path)
                if (!file.isFile || !file.canRead()) {
                    throw TranscodeException(ErrorCode.NOT_FOUND, "there is no readable file at ${source.path}")
                }
                Uri.fromFile(file)
            }
            is SourceLocation.Content -> {
                val uri = Uri.parse(source.uri)
                try {
                    context.contentResolver.openFileDescriptor(uri, "r")?.close()
                        ?: throw TranscodeException(ErrorCode.NOT_FOUND, "${source.uri} cannot be opened")
                } catch (e: TranscodeException) {
                    throw e
                } catch (e: Exception) {
                    throw TranscodeException(ErrorCode.NOT_FOUND, "${source.uri} cannot be opened: ${e.message}")
                }
                uri
            }
        }

    private data class Source(val width: Int, val height: Int, val rotation: Int, val hasAudio: Boolean)

    /** The stored width, height and rotation of the video track, and whether there is sound. */
    private fun probe(uri: Uri): Source {
        val retriever = MediaMetadataRetriever()
        try {
            try {
                retriever.setDataSource(context, uri)
            } catch (e: Exception) {
                throw TranscodeException(ErrorCode.NO_VIDEO, "$uri is not a video this device reads: ${e.message}")
            }
            if (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") {
                throw TranscodeException(ErrorCode.NO_VIDEO, "$uri has no video track")
            }
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (width <= 0 || height <= 0) throw TranscodeException(ErrorCode.NO_VIDEO, "$uri has a video track without a size")
            val hasAudio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            return Source(width, height, rotation, hasAudio)
        } finally {
            retriever.release()
        }
    }

    /** What was written, read back from the file. */
    private fun describe(file: File): TranscodeOutcome {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            val shown = Geometry.displayedSize(width, height, rotation)
            return TranscodeOutcome(file, shown.first, shown.second, duration, file.length())
        } finally {
            retriever.release()
        }
    }

    private companion object {
        const val PROGRESS_INTERVAL_MS = 200L
    }
}
