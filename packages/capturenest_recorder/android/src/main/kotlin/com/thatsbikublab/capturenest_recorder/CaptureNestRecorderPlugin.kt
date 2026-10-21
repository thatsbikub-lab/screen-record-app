package com.thatsbikublab.capturenest_recorder

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** Android bridge for system-approved MediaProjection recordings. */
class CaptureNestRecorderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {

    private lateinit var applicationContext: Context
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingOptions: Map<String, Any>? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (pendingResult != null || CaptureService.isRecording()) {
                    result.error("already_recording", "A capture is already in progress.", null)
                    return
                }
                @Suppress("UNCHECKED_CAST")
                val options = call.arguments as? Map<String, Any>
                if (options == null) {
                    result.error("bad_options", "Capture options are required.", null)
                    return
                }
                pendingOptions = options
                pendingResult = result
                requestAudioThenProjectionIfNeeded()
            }
            "stop" -> {
                val output = CaptureService.stopActive()
                if (output == null) result.error("not_recording", "There is no active capture.", null)
                else result.success(output)
            }
            "pause" -> {
                if (CaptureService.pauseActive()) result.success(null)
                else result.error("not_recording", "There is no active capture.", null)
            }
            "resume" -> {
                if (CaptureService.resumeActive()) result.success(null)
                else result.error("not_recording", "There is no active capture.", null)
            }
            "trim" -> trim(call, result)
            "saveToGallery" -> saveToGallery(call, result)
            else -> result.notImplemented()
        }
    }

    private fun requestAudioThenProjectionIfNeeded() {
        val host = activity
        if (host == null) {
            failPending("no_activity", "Open CaptureNest before starting a recording.")
            return
        }
        val wantsMicrophone = pendingOptions?.get("microphone") as? Boolean ?: false
        if (wantsMicrophone && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            ContextCompat.checkSelfPermission(host, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED
        ) {
            host.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), AUDIO_PERMISSION_REQUEST)
            return
        }
        requestProjection(host)
    }

    private fun requestProjection(host: Activity) {
        val manager = host.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        host.startActivityForResult(manager.createScreenCaptureIntent(), CAPTURE_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CAPTURE_REQUEST) return false
        if (resultCode != Activity.RESULT_OK || data == null) {
            failPending("capture_denied", "Screen capture permission was not granted.")
            return true
        }
        val options = pendingOptions ?: run {
            failPending("state_error", "Capture setup was interrupted.")
            return true
        }
        val intent = Intent(applicationContext, CaptureService::class.java).apply {
            action = CaptureService.ACTION_START
            putExtra(CaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(CaptureService.EXTRA_RESULT_DATA, data)
            putExtra(CaptureService.EXTRA_MICROPHONE, options["microphone"] as? Boolean ?: false)
            putExtra(CaptureService.EXTRA_DEVICE_AUDIO, options["deviceAudio"] as? Boolean ?: false)
            putExtra(CaptureService.EXTRA_FRONT_CAMERA, options["frontCamera"] as? Boolean ?: false)
            putExtra(CaptureService.EXTRA_QUALITY, options["quality"] as? String ?: "high")
        }
        ContextCompat.startForegroundService(applicationContext, intent)
        pendingResult?.success(null)
        clearPending()
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != AUDIO_PERMISSION_REQUEST) return false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) requestAudioThenProjectionIfNeeded()
        else failPending("audio_denied", "Microphone access is required when microphone capture is enabled.")
        return true
    }

    private fun trim(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("inputPath")
        val fromMs = call.argument<Number>("fromMs")?.toLong()
        val toMs = call.argument<Number>("toMs")?.toLong()
        if (path == null || fromMs == null || toMs == null || toMs <= fromMs) {
            result.error("bad_trim", "Choose a valid start and end time.", null)
            return
        }
        try {
            result.success(VideoTrimmer.trim(applicationContext, path, fromMs, toMs))
        } catch (error: Exception) {
            result.error("trim_failed", error.message, null)
        }
    }

    private fun saveToGallery(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("bad_path", "A video path is required.", null)
            return
        }
        try {
            GallerySaver.save(applicationContext, path)
            result.success(null)
        } catch (error: Exception) {
            result.error("gallery_failed", error.message, null)
        }
    }

    private fun failPending(code: String, message: String) {
        pendingResult?.error(code, message, null)
        clearPending()
    }

    private fun clearPending() {
        pendingOptions = null
        pendingResult = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val CHANNEL = "com.thatsbikublab.capturenest/recorder"
        private const val CAPTURE_REQUEST = 7142
        private const val AUDIO_PERMISSION_REQUEST = 7143
    }
}


