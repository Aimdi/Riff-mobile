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
                else -> result.notImplemented()
            }
        }
    }
}
