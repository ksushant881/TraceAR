package com.sushant.tracear

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.RectF
import android.media.ExifInterface
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

object TimelapseEncoder {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun encode(
        frameDir: String,
        outPath: String,
        fps: Int,
        onProgress: (Double) -> Unit,
        onSuccess: (String) -> Unit,
        onError: (String, String) -> Unit
    ) {
        executor.execute {
            try {
                val resultPath = encodeSync(frameDir, outPath, fps) { p ->
                    mainHandler.post { onProgress(p) }
                }
                mainHandler.post { onSuccess(resultPath) }
            } catch (e: Exception) {
                mainHandler.post {
                    onError("ENCODE_ERROR", e.message ?: "Timelapse encoding failed")
                }
            }
        }
    }

    private fun encodeSync(
        frameDir: String,
        outPath: String,
        fps: Int,
        onProgress: (Double) -> Unit
    ): String {
        val dir = File(frameDir)
        val frames = dir.listFiles { f ->
            f.isFile && (f.name.endsWith(".jpg", true) || f.name.endsWith(".jpeg", true))
        }?.sortedBy { it.name } ?: emptyList()

        if (frames.isEmpty()) {
            throw IllegalArgumentException("No JPEG frames found in $frameDir")
        }

        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(frames.first().absolutePath, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) {
            throw IllegalStateException("Invalid first frame dimensions")
        }
        // Camera JPEGs usually store unrotated sensor pixels plus an EXIF
        // orientation tag, which BitmapFactory ignores. Size the video for
        // the upright image.
        val firstRotation = exifRotationDegrees(frames.first().absolutePath)
        val swap = firstRotation == 90 || firstRotation == 270
        val rawW = if (swap) boundsOpts.outHeight else boundsOpts.outWidth
        val rawH = if (swap) boundsOpts.outWidth else boundsOpts.outHeight

        val longSide = max(rawW, rawH)
        val scale = if (longSide > 1920) 1920.0 / longSide else 1.0
        var width = (rawW * scale).toInt()
        var height = (rawH * scale).toInt()
        // Round to even numbers for H.264
        width = max(2, width and 1.inv())
        height = max(2, height and 1.inv())

        val safeFps = fps.coerceIn(1, 60)
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, safeFps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val outFile = File(outPath)
        outFile.parentFile?.mkdirs()
        if (outFile.exists()) outFile.delete()

        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = codec.createInputSurface()
        codec.start()

        val muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false
        var outFrameIndex = 0L
        val bufferInfo = MediaCodec.BufferInfo()

        fun drainEncoder(endOfStream: Boolean) {
            if (endOfStream) {
                codec.signalEndOfInputStream()
            }
            while (true) {
                val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                when {
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!endOfStream) break
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        if (muxerStarted) {
                            throw IllegalStateException("Output format changed twice")
                        }
                        trackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxerStarted = true
                    }
                    outputIndex >= 0 -> {
                        val encodedData = codec.getOutputBuffer(outputIndex)
                            ?: throw IllegalStateException("Null output buffer")
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                            bufferInfo.size = 0
                        }
                        if (bufferInfo.size != 0) {
                            if (!muxerStarted) {
                                throw IllegalStateException("Muxer hasn't started")
                            }
                            encodedData.position(bufferInfo.offset)
                            encodedData.limit(bufferInfo.offset + bufferInfo.size)
                            bufferInfo.presentationTimeUs =
                                outFrameIndex * 1_000_000L / safeFps
                            outFrameIndex++
                            muxer.writeSampleData(trackIndex, encodedData, bufferInfo)
                        }
                        codec.releaseOutputBuffer(outputIndex, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            break
                        }
                    }
                }
            }
        }

        try {
            val total = frames.size.toDouble()
            for ((index, frameFile) in frames.withIndex()) {
                val bitmap = decodeUprightBitmap(frameFile.absolutePath, width, height)
                val canvas = inputSurface.lockCanvas(null)
                try {
                    val srcRect = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
                    val dstRect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                    val matrix = Matrix().apply {
                        setRectToRect(srcRect, dstRect, Matrix.ScaleToFit.FILL)
                    }
                    canvas.drawBitmap(bitmap, matrix, null)
                } finally {
                    inputSurface.unlockCanvasAndPost(canvas)
                    bitmap.recycle()
                }
                drainEncoder(false)
                onProgress((index + 1) / total)
            }
            drainEncoder(true)
        } finally {
            try {
                codec.stop()
            } catch (_: Exception) {}
            codec.release()
            inputSurface.release()
            if (muxerStarted) {
                try {
                    muxer.stop()
                } catch (_: Exception) {}
            }
            muxer.release()
        }

        return outPath
    }

    /** Clockwise rotation (0/90/180/270) from the JPEG's EXIF orientation. */
    private fun exifRotationDegrees(path: String): Int {
        return try {
            when (ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )) {
                ExifInterface.ORIENTATION_ROTATE_90,
                ExifInterface.ORIENTATION_TRANSPOSE -> 90
                ExifInterface.ORIENTATION_ROTATE_180,
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> 180
                ExifInterface.ORIENTATION_ROTATE_270,
                ExifInterface.ORIENTATION_TRANSVERSE -> 270
                else -> 0
            }
        } catch (_: Exception) {
            0
        }
    }

    /** Decodes [path] downsampled for [reqWidth]x[reqHeight] and rotated upright. */
    private fun decodeUprightBitmap(path: String, reqWidth: Int, reqHeight: Int): Bitmap {
        val rotation = exifRotationDegrees(path)
        val swap = rotation == 90 || rotation == 270
        val decoded = decodeSampledBitmap(
            path,
            if (swap) reqHeight else reqWidth,
            if (swap) reqWidth else reqHeight
        )
        if (rotation == 0) return decoded
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        val rotated = Bitmap.createBitmap(
            decoded, 0, 0, decoded.width, decoded.height, matrix, true
        )
        if (rotated !== decoded) decoded.recycle()
        return rotated
    }

    private fun decodeSampledBitmap(path: String, reqWidth: Int, reqHeight: Int): Bitmap {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, opts)
        var inSampleSize = 1
        val halfH = opts.outHeight / 2
        val halfW = opts.outWidth / 2
        while (halfH / inSampleSize >= reqHeight && halfW / inSampleSize >= reqWidth) {
            inSampleSize *= 2
        }
        val decodeOpts = BitmapFactory.Options().apply {
            this.inSampleSize = inSampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeFile(path, decodeOpts)
            ?: throw IllegalStateException("Failed to decode frame: $path")
    }
}
