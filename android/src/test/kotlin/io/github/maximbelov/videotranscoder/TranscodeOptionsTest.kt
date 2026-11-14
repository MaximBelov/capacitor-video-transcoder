package io.github.maximbelov.videotranscoder

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class TranscodeOptionsTest {
    private fun parse(vararg pairs: Pair<String, Any?>): TranscodeOptions {
        val map = mapOf(*pairs)
        return TranscodeOptions.parse { map[it] }
    }

    private fun assertInvalid(vararg pairs: Pair<String, Any?>, mentioning: String? = null) {
        try {
            parse(*pairs)
            fail("expected INVALID_ARGUMENT for ${pairs.toList()}")
        } catch (e: TranscodeException) {
            assertEquals(ErrorCode.INVALID_ARGUMENT, e.code)
            if (mentioning != null) assertTrue(e.message, e.message!!.contains(mentioning))
        }
    }

    @Test
    fun fillsTheDefaults() {
        val options = parse("source" to "/sdcard/in.mp4")
        assertEquals(SourceLocation.File("/sdcard/in.mp4"), options.source)
        assertNull(options.destination)
        assertEquals(1280, options.maxSize)
        assertEquals(30_000L, options.maxDurationMs)
        assertEquals(1_800_000, options.videoBitrate)
    }

    @Test
    fun takesFileUrlsContentUrisAndTheNumbersJsonGives() {
        val options =
            parse(
                "source" to "content://com.android.providers.media.documents/document/video%3A42",
                "destination" to "file:///data/user/0/app/cache/My%20Video.mp4",
                "maxSize" to 640,
                "maxDurationMs" to 1500L,
                "videoBitrate" to 900000.0,
            )
        assertEquals(SourceLocation.Content("content://com.android.providers.media.documents/document/video%3A42"), options.source)
        assertEquals("/data/user/0/app/cache/My Video.mp4", options.destination)
        assertEquals(640, options.maxSize)
        assertEquals(1500L, options.maxDurationMs)
        assertEquals(900_000, options.videoBitrate)
        assertEquals(SourceLocation.File("/a b.mov"), parse("source" to "file:///a b.mov").source)
    }

    @Test
    fun refusesWhatIsNotALocalFile() {
        for (source in listOf("", "relative/in.mp4", "https://example.com/a.mp4", "content://", "file://", "/")) {
            assertInvalid("source" to source)
        }
        assertInvalid()
        assertInvalid("source" to 42)
        assertInvalid("source" to "/a.mp4", "destination" to "out.mp4", mentioning = "destination")
        assertInvalid("source" to "/a.mp4", "destination" to "content://x/y", mentioning = "destination")
        assertInvalid("source" to "/a.mp4", "destination" to 1, mentioning = "destination")
    }

    @Test
    fun refusesNumbersOutOfRangeOrNotWhole() {
        val bad =
            listOf(
                "maxSize" to 15,
                "maxSize" to 640.5,
                "maxSize" to "640",
                "maxSize" to true,
                "maxSize" to Double.NaN,
                "maxDurationMs" to 0,
                "maxDurationMs" to -1,
                "videoBitrate" to 0,
                "videoBitrate" to 1e12,
            )
        for ((key, value) in bad) assertInvalid("source" to "/a.mp4", key to value, mentioning = key)
        assertEquals(16, parse("source" to "/a.mp4", "maxSize" to 16).maxSize)
    }

    @Test
    fun writesFileUrls() {
        assertEquals("file:///tmp/out%20put.mp4", TranscodeOptions.fileUrl(File("/tmp/out put.mp4")))
    }
}

class GeometryTest {
    @Test
    fun scalesTheLongerSideDownToMaxSize() {
        assertEquals(1280 to 720, Geometry.outputSize(1920, 1080, 1280))
        assertEquals(720 to 1280, Geometry.outputSize(1080, 1920, 1280))
        assertEquals(1280 to 720, Geometry.outputSize(3840, 2160, 1280))
        assertEquals(1280 to 960, Geometry.outputSize(1440, 1080, 1280))
    }

    @Test
    fun neverScalesUpAndKeepsSidesEven() {
        assertEquals(640 to 360, Geometry.outputSize(640, 360, 1280))
        assertEquals(320 to 240, Geometry.outputSize(321, 241, 1280))
        assertEquals(1280 to 720, Geometry.outputSize(1920, 1080, 1281))
        assertEquals(1280 to 2, Geometry.outputSize(4000, 3, 1280))
    }

    @Test
    fun turnsTheSizeAsShown() {
        assertEquals(1080 to 1920, Geometry.displayedSize(1920, 1080, 90))
        assertEquals(1080 to 1920, Geometry.displayedSize(1920, 1080, -90))
        assertEquals(1080 to 1920, Geometry.displayedSize(1920, 1080, 270))
        assertEquals(1920 to 1080, Geometry.displayedSize(1920, 1080, 180))
        assertEquals(1920 to 1080, Geometry.displayedSize(1920, 1080, 0))
    }

    @Test
    fun progressStaysBelowOneUntilTheEnd() {
        assertEquals(0.0, Geometry.progress(0), 0.0)
        assertEquals(0.5, Geometry.progress(50), 0.0)
        assertEquals(0.99, Geometry.progress(100), 0.0)
        assertEquals(0.0, Geometry.progress(-3), 0.0)
    }
}
