package com.thatsbikublab.capturenest_recorder

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Environment
import java.io.File
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Fast MP4 trim that copies encoded samples without re-encoding the video. */
object VideoTrimmer {
    fun trim(context: Context, sourcePath: String, fromMs: Long, toMs: Long): String {
        val source = File(sourcePath)
        require(source.exists()) { "This recording no longer exists." }
        val directory = File(context.getExternalFilesDir(Environment.DIRECTORY_MOVIES), "CaptureNest")
        if (!directory.exists() && !directory.mkdirs()) error("Could not create the export folder.")
        val target = File(directory, "CaptureNest_trim_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4")
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val mapping = mutableMapOf<Int, Int>()
            var largestBuffer = 1_048_576
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                mapping[index] = (muxer ?: MediaMuxer(target.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).also { muxer = it }).addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    largestBuffer = maxOf(largestBuffer, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            require(mapping.isNotEmpty()) { "No playable video tracks were found." }
            muxer!!.start()
            mapping.keys.forEach(extractor::selectTrack)
            extractor.seekTo(fromMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val buffer = ByteBuffer.allocateDirect(largestBuffer)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val track = extractor.sampleTrackIndex
                if (track < 0) break
                val sampleTime = extractor.sampleTime
                if (sampleTime > toMs * 1000) break
                val mappedTrack = mapping[track]
                if (mappedTrack != null && sampleTime >= fromMs * 1000) {
                    buffer.clear()
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    info.set(0, size, sampleTime - fromMs * 1000, extractor.sampleFlags)
                    muxer!!.writeSampleData(mappedTrack, buffer, info)
                }
                extractor.advance()
            }
            return target.absolutePath
        } catch (error: Exception) {
            target.delete()
            throw error
        } finally {
            try { muxer?.stop() } catch (_: Exception) { }
            try { muxer?.release() } catch (_: Exception) { }
            extractor.release()
        }
    }
}


