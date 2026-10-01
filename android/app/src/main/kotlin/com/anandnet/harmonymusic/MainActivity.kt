package com.anandnet.harmonymusic

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : AudioServiceActivity() {

    /** Native ExoPlayer video engine (video mode). */
    private var videoPlayer: RiffVideoPlayer? = null

    /** `riff/apps`: needs this activity (startActivity, packageManager). */
    private var appsChannel: MethodChannel? = null

    // Deprecated on API 33 but still works everywhere; visible thanks to
    // the <queries> entries in the manifest.
    @Suppress("DEPRECATION")
    private fun isPackageInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // audio_service hands every activity the same cached engine, which
    // outlives them; configure/cleanUp run per activity attach/detach.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelOwner = WeakReference(this)
        videoPlayer?.dispose()
        videoPlayer = RiffVideoPlayer(
            applicationContext,
            flutterEngine.renderer,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Hand-off to other apps (WizeStream for YouTube podcasts).
        val apps = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/apps"
        )
        apps.setMethodCallHandler { call, result ->
            when (call.method) {
                "installedPackage" -> {
                    val candidates = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(candidates.firstOrNull { isPackageInstalled(it) })
                }
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    val pkg = call.argument<String>("package")
                    if (url.isNullOrEmpty() || pkg.isNullOrEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                .setPackage(pkg)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (_: SecurityException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        appsChannel = apps
        // Stream resolution + audio effects. Holds no activity and stays
        // registered after this activity goes: the Dart audio handler keeps
        // resolving tracks while the engine runs in the background.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/newpipe"
        ).setMethodCallHandler(NewPipeChannel)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // A newer activity may already have attached to the same engine and
        // taken over the channels; don't clear its handlers.
        val owner = channelOwner?.get() === this
        videoPlayer?.dispose(detachChannels = owner)
        videoPlayer = null
        if (owner) {
            appsChannel?.setMethodCallHandler(null)
            channelOwner = null
        }
        appsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        /** The activity whose handlers are currently on the engine's channels. */
        private var channelOwner: WeakReference<MainActivity>? = null
    }
}
