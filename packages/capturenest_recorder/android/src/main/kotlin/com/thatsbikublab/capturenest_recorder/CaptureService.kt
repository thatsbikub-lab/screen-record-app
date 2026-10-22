package com.thatsbikublab.capturenest_recorder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/** Owns the foreground session required by Android's MediaProjection API. */
class CaptureService : Service() {
    private var recorder: MediaRecorder? = null
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var outputPath: String? = null
    private var recording = false
    private var stopping = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> start(intent)
            ACTION_STOP -> stopRecording()
            ACTION_PAUSE -> recorder?.pause()
            ACTION_RESUME -> recorder?.resume()
        }
        return START_NOT_STICKY
    }

    private fun start(intent: Intent) {
        if (recording) return
        instance = this
        val wantsMic = intent.getBooleanExtra(EXTRA_MICROPHONE, false)
        startCaptureForegroundService(wantsMic)
        try {
            @Suppress("DEPRECATION")
            val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                ?: throw IllegalStateException("The screen capture approval expired.")
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(resultCode, resultData)
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopRecording()
                }
            }, null)

            val quality = intent.getStringExtra(EXTRA_QUALITY) ?: "high"
            val metrics = resources.displayMetrics
            val scaled = scaledSize(metrics.widthPixels, metrics.heightPixels, quality)
            val folder = File(getExternalFilesDir(Environment.DIRECTORY_MOVIES), "CaptureNest")
            if (!folder.exists() && !folder.mkdirs()) throw IllegalStateException("Could not create the recordings folder.")
            val name = "CaptureNest_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4"
            val output = File(folder, name)

            recorder = createRecorder(output, scaled.first, scaled.second, wantsMic, quality)
            display = projection?.createVirtualDisplay(
                "CaptureNest",
                scaled.first,
                scaled.second,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                recorder?.surface,
                null,
                null,
            )
            recorder?.start()
            outputPath = output.absolutePath
            recording = true
        } catch (error: Exception) {
            stopRecording(deletePartial = true)
        }
    }

    private fun createRecorder(
        output: File,
        width: Int,
        height: Int,
        microphone: Boolean,
        quality: String,
    ): MediaRecorder {
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else MediaRecorder()
        if (microphone) mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        mediaRecorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder.setOutputFile(output.absolutePath)
        mediaRecorder.setVideoSize(width, height)
        mediaRecorder.setVideoFrameRate(30)
        mediaRecorder.setVideoEncodingBitRate(
            when (quality) {
                "standard" -> 4_000_000
                "ultra" -> 14_000_000
                else -> 8_000_000
            },
        )
        mediaRecorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        if (microphone) {
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioEncodingBitRate(128_000)
            mediaRecorder.setAudioSamplingRate(44_100)
        }
        mediaRecorder.prepare()
        return mediaRecorder
    }

    private fun stopRecording(deletePartial: Boolean = false): String? {
        val finalPath = outputPath
        if (stopping) return finalPath
        stopping = true
        try {
            if (recording) recorder?.stop()
        } catch (_: RuntimeException) {
            if (finalPath != null) File(finalPath).delete()
        } finally {
            recording = false
            try { display?.release() } catch (_: Exception) { }
            try { projection?.stop() } catch (_: Exception) { }
            try { recorder?.reset() } catch (_: Exception) { }
            try { recorder?.release() } catch (_: Exception) { }
            display = null
            projection = null
            recorder = null
            stopping = false
            if (deletePartial && finalPath != null) File(finalPath).delete()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            instance = null
        }
        return finalPath
    }

    private fun startCaptureForegroundService(includeMicrophone: Boolean) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, getString(R.string.capturenest_capture_channel), NotificationManager.IMPORTANCE_LOW).apply {
                    description = getString(R.string.capturenest_capture_description)
                },
            )
        }
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle(getString(R.string.capturenest_capture_title))
            .setContentText(getString(R.string.capturenest_capture_description))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                (if (includeMicrophone) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (recording) stopRecording()
        super.onDestroy()
    }

    private fun scaledSize(width: Int, height: Int, quality: String): Pair<Int, Int> {
        val maxLongSide = when (quality) {
            "standard" -> 1280
            "ultra" -> 2560
            else -> 1920
        }
        val longSide = maxOf(width, height)
        val scale = minOf(1.0, maxLongSide.toDouble() / longSide)
        var outputWidth = (width * scale).roundToInt().coerceAtLeast(2)
        var outputHeight = (height * scale).roundToInt().coerceAtLeast(2)
        if (outputWidth % 2 != 0) outputWidth--
        if (outputHeight % 2 != 0) outputHeight--
        return outputWidth to outputHeight
    }

    companion object {
        const val ACTION_START = "com.thatsbikublab.capturenest.START"
        const val ACTION_STOP = "com.thatsbikublab.capturenest.STOP"
        const val ACTION_PAUSE = "com.thatsbikublab.capturenest.PAUSE"
        const val ACTION_RESUME = "com.thatsbikublab.capturenest.RESUME"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_MICROPHONE = "microphone"
        const val EXTRA_DEVICE_AUDIO = "deviceAudio"
        const val EXTRA_FRONT_CAMERA = "frontCamera"
        const val EXTRA_QUALITY = "quality"
        private const val CHANNEL_ID = "capturenest.capture"
        private const val NOTIFICATION_ID = 2281
        private var instance: CaptureService? = null

        fun isRecording(): Boolean = instance?.recording == true
        fun pauseActive(): Boolean = instance?.let {
            if (it.recording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                it.recorder?.pause()
                true
            } else false
        } ?: false

        fun resumeActive(): Boolean = instance?.let {
            if (it.recording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                it.recorder?.resume()
                true
            } else false
        } ?: false

        fun stopActive(): String? = instance?.stopRecording()
    }
}


