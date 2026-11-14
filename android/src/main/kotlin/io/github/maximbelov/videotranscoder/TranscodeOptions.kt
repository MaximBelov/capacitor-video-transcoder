package io.github.maximbelov.videotranscoder

import java.net.URI
import java.net.URISyntaxException

/** The `code` a call is rejected with: the names are the ones `src/definitions.ts` documents. */
enum class ErrorCode { INVALID_ARGUMENT, NOT_FOUND, NO_VIDEO, BUSY, CANCELLED, FAILED }

class TranscodeException(val code: ErrorCode, message: String) : Exception(message)

/** Where the source video is: a file, or a `content://` URI read through the content resolver. */
sealed class SourceLocation {
    data class File(val path: String) : SourceLocation()

    data class Content(val uri: String) : SourceLocation()
}

/** What a `transcode` call asked for, checked and with the defaults filled in. Pure Kotlin, so it is tested on the JVM. */
data class TranscodeOptions(
    val source: SourceLocation,
    /** An absolute path, or `null` when the call named none: a new file in the cache directory is used. */
    val destination: String? = null,
    val maxSize: Int = DEFAULT_MAX_SIZE,
    val maxDurationMs: Long = DEFAULT_MAX_DURATION_MS,
    val videoBitrate: Int = DEFAULT_VIDEO_BITRATE,
) {
    companion object {
        const val DEFAULT_MAX_SIZE = 1280
        const val DEFAULT_MAX_DURATION_MS = 30_000L
        const val DEFAULT_VIDEO_BITRATE = 1_800_000
        const val MINIMUM_MAX_SIZE = 16

        /** The options of a call, read one key at a time through [get], which answers `null` for a key that is absent or null. */
        fun parse(get: (String) -> Any?): TranscodeOptions {
            val source = get("source") as? String
            if (source.isNullOrEmpty()) {
                throw invalid("source is required: an absolute path, a file:// URL or a content:// URI")
            }
            val destination =
                when (val value = get("destination")) {
                    null -> null
                    is String -> filePath(value, "destination")
                    else -> throw invalid("destination must be a string")
                }
            return TranscodeOptions(
                source = sourceLocation(source),
                destination = destination,
                maxSize = wholeNumber(get("maxSize"), "maxSize", MINIMUM_MAX_SIZE, DEFAULT_MAX_SIZE),
                maxDurationMs = wholeNumber(get("maxDurationMs"), "maxDurationMs", 1, DEFAULT_MAX_DURATION_MS.toInt()).toLong(),
                videoBitrate = wholeNumber(get("videoBitrate"), "videoBitrate", 1, DEFAULT_VIDEO_BITRATE),
            )
        }

        fun sourceLocation(value: String): SourceLocation =
            if (value.startsWith("content://")) {
                if (value.length <= "content://".length) throw invalid("source is not a content:// URI: $value")
                SourceLocation.Content(value)
            } else {
                SourceLocation.File(filePath(value, "source"))
            }

        /** An absolute path or a `file://` URL as an absolute path. Anything else (a relative path, `http://`) is refused. */
        fun filePath(value: String, name: String): String {
            var path = value
            if (value.startsWith("file://")) {
                path =
                    try {
                        URI(value).path
                    } catch (e: URISyntaxException) {
                        null
                    } ?: value.removePrefix("file://").removePrefix("localhost")
            }
            if (!path.startsWith("/") || path.length < 2) {
                throw invalid("$name must be an absolute path or a file:// URL, not $value")
            }
            return path
        }

        /** A file as a `file:///` URL, with the escapes a URL needs. */
        fun fileUrl(file: java.io.File): String = file.absoluteFile.toURI().toString().replaceFirst("file:/", "file:///")

        private fun wholeNumber(value: Any?, name: String, minimum: Int, fallback: Int): Int {
            if (value == null) return fallback
            if (value !is Number) throw invalid("$name must be a number")
            val double = value.toDouble()
            if (double.isNaN() || double.isInfinite() || Math.rint(double) != double || double > Int.MAX_VALUE) {
                throw invalid("$name must be a whole number, not $value")
            }
            if (double < minimum) throw invalid("$name must be at least $minimum, not $value")
            return double.toInt()
        }

        private fun invalid(message: String) = TranscodeException(ErrorCode.INVALID_ARGUMENT, message)
    }
}

/** The arithmetic of the output. Pure, so it is tested without a video. */
object Geometry {
    /**
     * The size that fits a video into [maxSize] on its longer side, keeping the aspect ratio and never scaling up. Both sides are
     * rounded down to an even number (H.264 4:2:0 halves them for the chroma planes), and are at least 2. Integer arithmetic, so
     * 1920x1080 into 1280 is exactly 1280x720.
     */
    fun outputSize(width: Int, height: Int, maxSize: Int): Pair<Int, Int> {
        val w = maxOf(Math.abs(width), 1).toLong()
        val h = maxOf(Math.abs(height), 1).toLong()
        val longer = maxOf(w, h)
        val limit = maxOf(maxSize, 2).toLong()
        fun fit(side: Long): Int {
            val scaled = if (longer > limit) side * limit / longer else side
            return maxOf(2L, scaled / 2 * 2).toInt()
        }
        return fit(w) to fit(h)
    }

    /** A stored size as a player shows it, with the rotation applied. */
    fun displayedSize(width: Int, height: Int, rotationDegrees: Int): Pair<Int, Int> =
        if (Math.floorMod(rotationDegrees, 180) == 0) width to height else height to width

    /** A percentage from Media3 as progress from 0 to 1, held below 1 until the file is finished. */
    fun progress(percent: Int): Double = (percent.coerceIn(0, 100) / 100.0).coerceAtMost(0.99)
}
