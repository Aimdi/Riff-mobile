package com.anandnet.harmonymusic

import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {

    private val resolverExecutor = Executors.newSingleThreadExecutor()

    // Native audio-effect chain bound to the player's audio session
    // (RiPlay-style). All effects are held so they survive across calls and
    // are recreated if the session id changes (new ExoPlayer instance).
    private var bassBoost: android.media.audiofx.BassBoost? = null
    private var loudnessEnhancer: android.media.audiofx.LoudnessEnhancer? = null
    private var reverb: android.media.audiofx.PresetReverb? = null
    private var virtualizer: android.media.audiofx.Virtualizer? = null
    private var fxSessionId: Int = 0

    private fun ensureSession(sessionId: Int) {
        if (fxSessionId == sessionId && bassBoost != null) return
        releaseFx()
        fxSessionId = sessionId
        try { bassBoost = android.media.audiofx.BassBoost(0, sessionId) } catch (_: Throwable) {}
        try { loudnessEnhancer = android.media.audiofx.LoudnessEnhancer(sessionId) } catch (_: Throwable) {}
        try { reverb = android.media.audiofx.PresetReverb(0, sessionId) } catch (_: Throwable) {}
        try { virtualizer = android.media.audiofx.Virtualizer(0, sessionId) } catch (_: Throwable) {}
    }

    private fun releaseFx() {
        try { bassBoost?.release() } catch (_: Throwable) {}
        try { loudnessEnhancer?.release() } catch (_: Throwable) {}
        try { reverb?.release() } catch (_: Throwable) {}
        try { virtualizer?.release() } catch (_: Throwable) {}
        bassBoost = null; loudnessEnhancer = null; reverb = null; virtualizer = null
    }

    private fun applyBassBoost(sessionId: Int, strength: Int) {
        try {
            ensureSession(sessionId)
            val s = strength.coerceIn(0, 1000)
            bassBoost?.enabled = s > 0
            if (s > 0) bassBoost?.setStrength(s.toShort())
        } catch (_: Throwable) {}
    }

    // gainMb: target gain in millibels (0 = off; negative attenuates, positive
    // amplifies — proper two-way loudness normalization + volume boost).
    private fun applyLoudness(sessionId: Int, gainMb: Int) {
        try {
            ensureSession(sessionId)
            loudnessEnhancer?.enabled = gainMb != 0
            if (gainMb != 0) loudnessEnhancer?.setTargetGain(gainMb.coerceIn(-2000, 2000))
        } catch (_: Throwable) {}
    }

    // preset: 0 none, 1 smallroom .. 6 plate (android PresetReverb presets).
    private fun applyReverb(sessionId: Int, preset: Int) {
        try {
            ensureSession(sessionId)
            reverb?.enabled = preset > 0
            reverb?.preset = preset.coerceIn(0, 6).toShort()
        } catch (_: Throwable) {}
    }

    private fun applyVirtualizer(sessionId: Int, strength: Int) {
        try {
            ensureSession(sessionId)
            val s = strength.coerceIn(0, 1000)
            virtualizer?.enabled = s > 0
            if (s > 0) virtualizer?.setStrength(s.toShort())
        } catch (_: Throwable) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val mainHandler = Handler(Looper.getMainLooper())
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/newpipe"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioStreams" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrEmpty()) {
                        result.error("ARG", "videoId missing", null)
                        return@setMethodCallHandler
                    }
                    resolverExecutor.execute {
                        try {
                            val streams = NewPipeResolver.getAudioStreams(videoId)
                            val json = JSONArray(
                                streams.map { JSONObject(it) }).toString()
                            mainHandler.post { result.success(json) }
                        } catch (e: Throwable) {
                            mainHandler.post {
                                result.error("NEWPIPE", e.toString(), null)
                            }
                        }
                    }
                }
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("ARG", "url missing", null)
                        return@setMethodCallHandler
                    }
                    result.success(
                        android.webkit.CookieManager.getInstance().getCookie(url))
                }
                "clearCookies" -> {
                    android.webkit.CookieManager.getInstance()
                        .removeAllCookies { ok -> result.success(ok) }
                }
                "setAudioFx" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    if (sessionId == 0) {
                        result.error("ARG", "sessionId missing", null)
                        return@setMethodCallHandler
                    }
                    applyBassBoost(sessionId, call.argument<Int>("bass") ?: 0)
                    applyLoudness(sessionId, call.argument<Int>("loudnessMb") ?: 0)
                    applyReverb(sessionId, call.argument<Int>("reverb") ?: 0)
                    applyVirtualizer(sessionId, call.argument<Int>("virtualizer") ?: 0)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
