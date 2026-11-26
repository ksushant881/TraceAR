package com.sushant.tracear

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.sushant.tracear/native"
        private const val PROGRESS_CHANNEL = "com.sushant.tracear/native/timelapse_progress"
    }

    private var progressSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "encodeTimelapse" -> {
                        val frameDir = call.argument<String>("frameDir")
                        val outPath = call.argument<String>("outPath")
                        val fps = call.argument<Int>("fps") ?: 24
                        if (frameDir.isNullOrEmpty() || outPath.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "frameDir and outPath are required", null)
                            return@setMethodCallHandler
                        }
                        TimelapseEncoder.encode(
                            frameDir = frameDir,
                            outPath = outPath,
                            fps = fps,
                            onProgress = { progress ->
                                progressSink?.success(progress)
                            },
                            onSuccess = { path ->
                                result.success(path)
                            },
                            onError = { code, message ->
                                result.error(code, message, null)
                            }
                        )
                    }
                    "getVideoThumbnail" -> {
                        val videoPath = call.argument<String>("videoPath")
                        if (videoPath.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(videoPath)
                            val bmp = retriever.getFrameAtTime(0)
                            retriever.release()
                            if (bmp != null) {
                                val stream = ByteArrayOutputStream()
                                bmp.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                bmp.recycle()
                                result.success(stream.toByteArray())
                            } else {
                                result.success(null)
                            }
                        } catch (_: Exception) {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
