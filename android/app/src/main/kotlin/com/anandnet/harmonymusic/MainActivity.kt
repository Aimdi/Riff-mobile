package com.anandnet.harmonymusic

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.speech.RecognizerIntent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : AudioServiceActivity() {

    /** Native ExoPlayer video engine (video mode). */
    private var videoPlayer: RiffVideoPlayer? = null

    /** Song recognition microphone (`riff/mic`). */
    private var micRecorder: MicRecorder? = null

    /** `riff/apps`: needs this activity (startActivity, packageManager). */
    private var appsChannel: MethodChannel? = null

    /** In-app voice search: the open `listen` call, answered with what was said. */
    private var speechResult: MethodChannel.Result? = null

    /** The phone's speech recognition ("Speak now"), one result. */
    private fun speechIntent(prompt: String?) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            .apply {
                if (!prompt.isNullOrEmpty()) putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            }

    // Deprecated on API 33 but still works everywhere; visible thanks to
    // the <queries> entries in the manifest.
    @Suppress("DEPRECATION")
    private fun isPackageInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // "Play … on Riff" from the Assistant arrives as MEDIA_PLAY_FROM_SEARCH
    // with the request in its extras. Given a riff://voice?q=… link
    // instead, app_links hands it to Dart like the icon's shortcuts, and
    // Dart plays it as Android Auto's voice search does.
    override fun onCreate(savedInstanceState: Bundle?) {
        voiceSearchAsLink(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        voiceSearchAsLink(intent)
        super.onNewIntent(intent)
    }

    private fun voiceSearchAsLink(intent: Intent?) {
        if (intent == null ||
            intent.action != MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH
        ) return
        intent.data = Uri.Builder()
            .scheme("riff")
            .authority("voice")
            .appendQueryParameter("q", intent.getStringExtra(SearchManager.QUERY) ?: "")
            .build()
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
        micRecorder?.stop()
        micRecorder = MicRecorder(flutterEngine.dartExecutor.binaryMessenger)
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
                // The app icon's long-press shortcuts, labelled in the
                // app's own language.
                "setShortcuts" -> result.success(
                    setShortcuts(
                        call.argument<List<Map<String, String>>>("shortcuts")
                            ?: emptyList()
                    )
                )
                // In-app voice search (the search field's mic): whether the
                // phone can listen, and what it heard (null: cancelled).
                "canListen" -> result.success(
                    speechIntent(null).resolveActivity(packageManager) != null
                )
                "listen" -> {
                    // One at a time: one still open hears nothing.
                    speechResult?.success(null)
                    speechResult = null
                    try {
                        startActivityForResult(
                            speechIntent(call.argument<String>("prompt")),
                            SPEECH_REQUEST
                        )
                        speechResult = result
                    } catch (_: ActivityNotFoundException) {
                        result.success(null)
                    } catch (_: SecurityException) {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        appsChannel = apps
        // Stream resolution + audio effects. Holds no activity and stays
        // registered after this activity goes: the Dart audio handler keeps
        // resolving tracks while the engine runs in the background.
        NewPipeChannel.appContext = applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/newpipe"
        ).setMethodCallHandler(NewPipeChannel)
        // The home screen widget's channel: like riff/newpipe it stays after
        // this activity goes, so the widget follows the music in the
        // background.
        NowPlayingWidget.appContext = applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/widget"
        ).setMethodCallHandler(NowPlayingWidget.channel)
        // Shakes for "Shake to restart" the sleep timer: also stays, as the
        // timer runs on with the screen off.
        ShakeChannel.appContext = applicationContext
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/shake"
        ).setStreamHandler(ShakeChannel)
        // Metered or not, for downloads that wait for Wi-Fi: also stays, as
        // the Inbox can refresh in the background.
        NetworkChannel.appContext = applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/network"
        ).setMethodCallHandler(NetworkChannel)
        // Online or not, for passing over songs that need a connection
        // while there's none: also stays, as play goes on in the background.
        ConnectionChannel.appContext = applicationContext
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "riff/network/online"
        ).setStreamHandler(ConnectionChannel)
    }

    /**
     * Long-press shortcuts on the app icon (Android 7.1+): [items] are
     * {id, label, uri}; each opens [MainActivity] with its uri, which
     * app_links hands to Dart like a shared link. Ids without an icon are
     * left out. False when they couldn't be set.
     */
    private fun setShortcuts(items: List<Map<String, String>>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return false
        val manager = getSystemService(ShortcutManager::class.java) ?: return false
        val shortcuts = items.mapNotNull { item ->
            val id = item["id"] ?: return@mapNotNull null
            val label = item["label"]
            val uri = item["uri"]
            val icon = SHORTCUT_ICONS[id]
            if (label.isNullOrEmpty() || uri.isNullOrEmpty() || icon == null) {
                return@mapNotNull null
            }
            ShortcutInfo.Builder(this, id)
                .setShortLabel(label)
                .setIcon(Icon.createWithResource(this, icon))
                .setIntent(
                    Intent(Intent.ACTION_VIEW, Uri.parse(uri), this, MainActivity::class.java)
                )
                .build()
        }
        return try {
            manager.setDynamicShortcuts(shortcuts)
        } catch (_: IllegalStateException) {
            // Rate limited: only happens while the app is in the background.
            false
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun lastExitInfo(): Map<String, Any?>? =
        systemExitInfo() ?: javaCrashInfo()

    /**
     * The trace [recordJavaCrashes] wrote, as an exit record: Android keeps
     * none before API 30, and may have dropped or never kept the system one.
     */
    private fun javaCrashInfo(): Map<String, Any?>? = try {
        val file = java.io.File(filesDir, CRASH_FILE)
        if (!file.exists()) null else mapOf(
            "reason" to "crash",
            "description" to "uncaught exception",
            "timestamp" to file.lastModified(),
            "importance" to 0,
            "trace" to file.readText().take(6000),
        )
    } catch (_: Exception) {
        null
    }

    private fun systemExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = getSystemService(ActivityManager::class.java) ?: return null
            // The newest exits first; swipes-away and normal exits are
            // skipped so a crash before them is still found.
            var info: ApplicationExitInfo? = null
            var reason: String? = null
            for (candidate in am.getHistoricalProcessExitReasons(packageName, 0, 5)) {
                reason = when (candidate.reason) {
                    ApplicationExitInfo.REASON_CRASH -> "crash"
                    ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash"
                    ApplicationExitInfo.REASON_ANR -> "not responding"
                    ApplicationExitInfo.REASON_LOW_MEMORY -> "low memory"
                    ApplicationExitInfo.REASON_SIGNALED -> "signal"
                    ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource usage"
                    ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "startup failure"
                    ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency died"
                    else -> null
                }
                if (reason != null) {
                    info = candidate
                    break
                }
            }
            if (info == null || reason == null) return null
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SPEECH_REQUEST) {
            val heard = if (resultCode == RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            } else {
                null
            }
            speechResult?.success(heard)
            speechResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // A newer activity may already have attached to the same engine and
        // taken over the channels; don't clear its handlers.
        val owner = channelOwner?.get() === this
        videoPlayer?.dispose(detachChannels = owner)
        videoPlayer = null
        micRecorder?.stop()
        micRecorder = null
        // A listen still open when the activity goes hears nothing.
        speechResult?.success(null)
        speechResult = null
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

/** startActivityForResult code of in-app voice search. */
private const val SPEECH_REQUEST = 7301
private var crashHandlerInstalled = false

/** App icon shortcut ids (lib/services/app_shortcuts.dart) and their icons. */
private val SHORTCUT_ICONS = mapOf(
    "search" to R.drawable.ic_shortcut_search,
    "liked" to R.drawable.ic_shortcut_liked,
    "downloads" to R.drawable.ic_shortcut_downloads,
)

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
