package io.github.maximbelov.videotranscoder

import com.getcapacitor.Logger

class VideoTranscoder {

    fun echo(value: String): String {
        Logger.info("Echo", value)

        return value
    }
}
