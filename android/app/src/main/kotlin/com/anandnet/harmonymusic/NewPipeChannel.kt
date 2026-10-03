package com.anandnet.harmonymusic

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * `riff/newpipe` handler: stream resolution, WebView cookies and the audio
 * effect chain.
 *
 * Process-wide on purpose: audio_service keeps the Flutter engine (and the
 * Dart audio handler that calls this channel) alive after the activity is
 * gone, so nothing here may hold on to an activity. Re-registering it on
 * every activity attach is idempotent.
 */
object NewPipeChannel : MethodChannel.MethodCallHandler {

    private val main = Handler(Looper.getMainLooper())

    /** Application context (never an activity), for system services. */
    @Volatile
    var appContext: Context? = null

    /**
     * A few resolutions run side by side so a user's skip doesn't queue
     * behind prefetches (each can take up to a connect + read timeout).
     */
    private val executor = ThreadPoolExecutor(
        3, 3, 30, TimeUnit.SECONDS, LinkedBlockingQueue(),
        object : ThreadFactory {
            private val n = AtomicInteger()
            override fun newThread(r: Runnable) =
                Thread(r, "riff-newpipe-${n.incrementAndGet()}").apply { isDaemon = true }
        },
    ).apply { allowCoreThreadTimeOut(true) }

    /**
     * Requests being resolved, by method + videoId + session; later callers
     * for the same key wait for the same extraction. Main thread only.
     */
    private val inFlight = HashMap<String, MutableList<MethodChannel.Result>>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAudioStreams", "getMuxedVideoStreams", "getVideoStreams" ->
                resolve(call, result)
            // Car UI mode (Android Auto on the phone): the Dart audio handler
            // uses it to tell Android Auto commands from notification ones.
            "isCarMode" -> {
                val ui = appContext?.getSystemService(Context.UI_MODE_SERVICE)
                    as? UiModeManager
                result.success(
                    ui?.currentModeType == Configuration.UI_MODE_TYPE_CAR)
            }
            "getCookies" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("ARG", "url missing", null)
                    return
                }
                result.success(
                    android.webkit.CookieManager.getInstance().getCookie(url))
            }
            "clearCookies" -> {
                // Signed out: drop extractions made with the old session.
                NewPipeResolver.clearCache()
                android.webkit.CookieManager.getInstance()
                    .removeAllCookies { ok -> result.success(ok) }
            }
            "setAudioFx" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                if (sessionId == 0) {
                    result.error("ARG", "sessionId missing", null)
                    return
                }
                AudioFx.apply(
                    sessionId,
                    bass = call.argument<Int>("bass") ?: 0,
                    loudnessMb = call.argument<Int>("loudnessMb") ?: 0,
                    reverb = call.argument<Int>("reverb") ?: 0,
                    virtualizer = call.argument<Int>("virtualizer") ?: 0,
                )
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun resolve(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method
        val videoId = call.argument<String>("videoId")
        if (videoId.isNullOrEmpty()) {
            result.error("ARG", "videoId missing", null)
            return
        }
        val cookie = call.argument<String>("cookie")
        val authorization = call.argument<String>("authorization")
        val key = listOf(method, videoId, cookie ?: "", authorization ?: "")
            .joinToString("\u0000")
        inFlight[key]?.let {
            it.add(result)
            return
        }
        inFlight[key] = mutableListOf(result)
        try {
            executor.execute {
                val outcome: Any = try {
                    NewPipeResolver.setAuth(cookie, authorization)
                    val streams = when (method) {
                        "getAudioStreams" -> NewPipeResolver.getAudioStreams(videoId)
                        "getMuxedVideoStreams" -> NewPipeResolver.getMuxedVideoStreams(videoId)
                        else -> NewPipeResolver.getVideoStreams(videoId)
                    }
                    JSONArray(streams.map { JSONObject(it) }).toString()
                } catch (e: Throwable) {
                    e
                } finally {
                    NewPipeResolver.setAuth(null, null)
                }
                main.post { finish(key, outcome) }
            }
        } catch (e: RejectedExecutionException) {
            finish(key, e)
        }
    }

    /** Replies to every caller waiting on [key], each exactly once. */
    private fun finish(key: String, outcome: Any) {
        val waiting = inFlight.remove(key) ?: return
        for (r in waiting) {
            try {
                if (outcome is String) {
                    r.success(outcome)
                } else {
                    r.error("NEWPIPE", describe(outcome as Throwable), null)
                }
            } catch (_: Throwable) {
            }
        }
    }

    /**
     * Error text for Dart. A captcha / HTTP 429 is spelled out the way the
     * Dart side recognises a bot check, so it retries with the signed-in
     * session.
     */
    internal fun describe(e: Throwable): String {
        val botCheck = generateSequence(e) { it.cause }.take(8)
            .any { it is ReCaptchaException }
        return if (botCheck) {
            "$e (YouTube wants to sign in to confirm you're not a bot)"
        } else {
            e.toString()
        }
    }
}

/**
 * Native audio-effect chain bound to the music player's audio session
 * (RiPlay-style). One per process: the audio session outlives activities, so
 * a recreated activity reuses these instead of stacking another set.
 */
object AudioFx {
    private var bassBoost: android.media.audiofx.BassBoost? = null
    private var loudnessEnhancer: android.media.audiofx.LoudnessEnhancer? = null
    private var reverb: android.media.audiofx.PresetReverb? = null
    private var virtualizer: android.media.audiofx.Virtualizer? = null
    private var fxSessionId: Int = 0

    /**
     * Whether the chain was built for [fxSessionId]. Tracked on its own: an
     * effect the device can't create stays null, and that must not rebuild
     * (and reset) the others on every call.
     */
    private var fxInitialised = false

    @Synchronized
    fun apply(sessionId: Int, bass: Int, loudnessMb: Int, reverb: Int, virtualizer: Int) {
        applyBassBoost(sessionId, bass)
        applyLoudness(sessionId, loudnessMb)
        applyReverb(sessionId, reverb)
        applyVirtualizer(sessionId, virtualizer)
    }

    private fun ensureSession(sessionId: Int) {
        if (fxInitialised && fxSessionId == sessionId) return
        release()
        fxSessionId = sessionId
        try { bassBoost = android.media.audiofx.BassBoost(0, sessionId) } catch (_: Throwable) {}
        try { loudnessEnhancer = android.media.audiofx.LoudnessEnhancer(sessionId) } catch (_: Throwable) {}
        try { reverb = android.media.audiofx.PresetReverb(0, sessionId) } catch (_: Throwable) {}
        try { virtualizer = android.media.audiofx.Virtualizer(0, sessionId) } catch (_: Throwable) {}
        fxInitialised = true
    }

    @Synchronized
    fun release() {
        try { bassBoost?.release() } catch (_: Throwable) {}
        try { loudnessEnhancer?.release() } catch (_: Throwable) {}
        try { reverb?.release() } catch (_: Throwable) {}
        try { virtualizer?.release() } catch (_: Throwable) {}
        bassBoost = null; loudnessEnhancer = null; reverb = null; virtualizer = null
        fxSessionId = 0
        fxInitialised = false
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
}
