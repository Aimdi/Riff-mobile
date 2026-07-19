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

    // Native bass boost bound to the player's audio session. Held so the
    // effect survives across setBassBoost calls; recreated if the session
    // id changes (new ExoPlayer instance).
    private var bassBoost: android.media.audiofx.BassBoost? = null
    private var bassSessionId: Int = 0
    private var bassStrength: Int = 0

    private fun applyBassBoost(sessionId: Int, strength: Int) {
        try {
            if (bassBoost == null || bassSessionId != sessionId) {
                bassBoost?.release()
                bassBoost = android.media.audiofx.BassBoost(0, sessionId)
                bassSessionId = sessionId
            }
            bassStrength = strength.coerceIn(0, 1000)
            bassBoost?.enabled = bassStrength > 0
            if (bassStrength > 0) {
                bassBoost?.setStrength(bassStrength.toShort())
            }
        } catch (e: Throwable) {
            // Some devices/effects reject a session; fail quietly.
        }
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
                "setBassBoost" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    val strength = call.argument<Int>("strength") ?: 0
                    if (sessionId == 0) {
                        result.error("ARG", "sessionId missing", null)
                        return@setMethodCallHandler
                    }
                    applyBassBoost(sessionId, strength)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
