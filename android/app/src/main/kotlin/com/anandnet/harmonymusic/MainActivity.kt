package com.anandnet.harmonymusic

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
        recordJavaCrashes(applicationContext)
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
                // Why the previous run ended (crash, native crash, ANR …),
                // so a crash on a user's phone can be reported without adb.
                "lastExitInfo" -> result.success(lastExitInfo())
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

    private fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = getSystemService(ActivityManager::class.java) ?: return null
            val info = am.getHistoricalProcessExitReasons(packageName, 0, 1)
                .firstOrNull() ?: return null
            val reason = when (info.reason) {
                ApplicationExitInfo.REASON_CRASH -> "crash"
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash"
                ApplicationExitInfo.REASON_ANR -> "not responding"
                ApplicationExitInfo.REASON_LOW_MEMORY -> "low memory"
                ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource usage"
                ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "startup failure"
                else -> null
            } ?: return null
            val trace = try {
                info.traceInputStream?.use { stream ->
                    val bytes = ByteArray(6000)
                    val n = stream.read(bytes)
                    if (n > 0) String(bytes, 0, n) else null
                }
            } catch (_: Exception) {
                null
            } ?: javaCrashTrace(info.timestamp)
            mapOf(
                "reason" to reason,
                "description" to info.description,
                "timestamp" to info.timestamp,
                "importance" to info.importance,
                "trace" to trace,
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Android keeps no stack trace for a Java/Kotlin crash (only for ANRs and
     * native crashes): read the one [recordJavaCrashes] wrote, if it belongs
     * to the exit at [exitMs].
     */
    private fun javaCrashTrace(exitMs: Long): String? = try {
        val file = java.io.File(filesDir, CRASH_FILE)
        if (file.exists() && kotlin.math.abs(file.lastModified() - exitMs) < 60_000) {
            file.readText().take(6000)
        } else {
            null
        }
    } catch (_: Exception) {
        null
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

private const val CRASH_FILE = "last_crash.txt"
private var crashHandlerInstalled = false

/**
 * Writes the stack trace of an uncaught Java/Kotlin exception (any thread:
 * ExoPlayer, the media session, plugins) to [CRASH_FILE] before the default
 * handler kills the process, so the next launch can offer it.
 */
internal fun recordJavaCrashes(context: android.content.Context) {
    if (crashHandlerInstalled) return
    crashHandlerInstalled = true
    val previous = Thread.getDefaultUncaughtExceptionHandler()
    val dir = context.filesDir
    Thread.setDefaultUncaughtExceptionHandler { thread, error ->
        try {
            java.io.File(dir, CRASH_FILE)
                .writeText("Thread: ${thread.name}\n${android.util.Log.getStackTraceString(error)}")
        } catch (_: Throwable) {
        }
        previous?.uncaughtException(thread, error)
    }
}
