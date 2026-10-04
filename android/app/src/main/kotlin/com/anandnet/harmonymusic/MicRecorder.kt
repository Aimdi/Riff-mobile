package com.anandnet.harmonymusic

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

/**
 * Microphone capture for song recognition ("riff/mic"): 16 kHz mono
 * 16-bit PCM, streamed to Dart in chunks on "riff/mic/pcm". Same format as
 * Audire's AudioRecorder (https://github.com/alexmercerind/audire).
 * The caller asks for RECORD_AUDIO before "start".
 */
class MicRecorder(messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var record: AudioRecord? = null
    @Volatile private var running = false
    private var thread: Thread? = null

    init {
        MethodChannel(messenger, "riff/mic").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "riff/mic/pcm").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                    stop()
                }
            })
    }

    @SuppressLint("MissingPermission")
    private fun start(): Boolean {
        if (running) return true
        val minSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL, ENCODING)
        if (minSize <= 0) return false
        val size = max(minSize * 4, SAMPLE_RATE * 2 / 4) // >= 250 ms
        val r = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, CHANNEL, ENCODING, size)
        } catch (_: Exception) {
            return false
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        try {
            r.startRecording()
        } catch (_: Exception) {
            r.release()
            return false
        }
        record = r
        running = true
        thread = Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val buf = ByteArray(SAMPLE_RATE * 2 / 4) // 250 ms
            while (running) {
                val n = r.read(buf, 0, buf.size)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    main.post { sink?.success(chunk) }
                } else if (n < 0) {
                    break
                }
            }
        }.also { it.start() }
        return true
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        record?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            it.release()
        }
        record = null
    }

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL = AudioFormat.CHANNEL_IN_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }
}
