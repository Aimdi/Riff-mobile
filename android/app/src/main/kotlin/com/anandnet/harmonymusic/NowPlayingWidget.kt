package com.anandnet.harmonymusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The home screen widget: the song or episode playing (art, title,
 * artist) with previous, play/pause and next. Dart sends what to show on
 * "riff/widget" (lib/services/now_playing_widget.dart); it's kept in
 * SharedPreferences, so the widget can draw itself while Riff isn't running.
 *
 * The buttons come back here and go on to audio_service's media button
 * receiver with the keys the notification's buttons send. While Riff isn't
 * running (nothing has updated the widget in this process) they open Riff.
 */
class NowPlayingWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.action?.let { BUTTON_KEYS[it] }
        if (key == null) {
            super.onReceive(context, intent)
            return
        }
        if (dartRunning) {
            context.sendBroadcast(
                Intent(Intent.ACTION_MEDIA_BUTTON)
                    .setComponent(ComponentName(context, MEDIA_BUTTON_RECEIVER))
                    .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, key))
            )
            return
        }
        // Riff isn't running: open it, and let the buttons open it straight
        // away from now on.
        try {
            context.startActivity(openIntent(context))
        } catch (_: Exception) {
        }
        refresh(context)
    }

    companion object {
        /** Set by MainActivity: the channel needs no activity. */
        var appContext: Context? = null

        /**
         * Whether Dart has updated the widget since this process started,
         * i.e. Riff is running and the buttons can go to its player.
         */
        @Volatile
        private var dartRunning = false

        private const val PREFS = "riff_widget"
        private val TEXT_KEYS = listOf("title", "artist", "art", "play", "pause", "next", "previous")

        private const val MEDIA_BUTTON_RECEIVER = "com.ryanheise.audioservice.MediaButtonReceiver"
        private const val ACTION_PLAY = "riff.widget.PLAY"
        private const val ACTION_PAUSE = "riff.widget.PAUSE"
        private const val ACTION_NEXT = "riff.widget.NEXT"
        private const val ACTION_PREVIOUS = "riff.widget.PREVIOUS"

        /**
         * The keys audio_service's notification buttons send: its "bypass"
         * keys for play and pause (play() and pause() straight away), the
         * media keys for next and previous.
         */
        private val BUTTON_KEYS = mapOf(
            ACTION_PLAY to KeyEvent.KEYCODE_MUTE,
            ACTION_PAUSE to KeyEvent.KEYCODE_MEDIA_RECORD,
            ACTION_NEXT to KeyEvent.KEYCODE_MEDIA_NEXT,
            ACTION_PREVIOUS to KeyEvent.KEYCODE_MEDIA_PREVIOUS,
        )

        /** Riff green and the black on it, until Dart sends the accent. */
        private val DEFAULT_ACCENT = 0xFF1DB954.toInt()
        private val DEFAULT_ON_ACCENT = 0xFF000000.toInt()

        private const val ART_DP = 48f
        private const val ART_RADIUS_DP = 8f

        private val renderer = Executors.newSingleThreadExecutor()

        /** "riff/widget": {title, artist, art, playing, accent, onAccent, labels}. */
        val channel = MethodChannel.MethodCallHandler { call, result ->
            val context = appContext
            if (call.method != "update") {
                result.notImplemented()
            } else if (context == null) {
                result.error("unavailable", "No context yet", null)
            } else {
                save(context, call)
                result.success(null)
            }
        }

        private fun save(context: Context, call: MethodCall) {
            dartRunning = true
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            for (key in TEXT_KEYS) editor.putString(key, call.argument<String>(key))
            editor.putBoolean("playing", call.argument<Boolean>("playing") == true)
            call.argument<Number>("accent")?.let { editor.putInt("accent", it.toInt()) }
            call.argument<Number>("onAccent")?.let { editor.putInt("onAccent", it.toInt()) }
            editor.apply()
            refresh(context)
        }

        /** Redraws every widget from what Dart last sent, off the main thread. */
        private fun refresh(context: Context) {
            val app = context.applicationContext
            renderer.execute {
                val manager = AppWidgetManager.getInstance(app)
                val ids = manager.getAppWidgetIds(ComponentName(app, NowPlayingWidget::class.java))
                render(app, manager, ids)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            if (ids.isEmpty()) return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val live = dartRunning
            val playing = live && prefs.getBoolean("playing", false)
            val views = RemoteViews(context.packageName, R.layout.widget_now_playing)

            val title = prefs.getString("title", null)
            views.setTextViewText(
                R.id.widget_title,
                if (title.isNullOrEmpty()) context.getString(R.string.widget_name) else title
            )
            val artist = if (title.isNullOrEmpty()) null else prefs.getString("artist", null)
            views.setTextViewText(R.id.widget_artist, artist ?: "")
            views.setViewVisibility(
                R.id.widget_artist,
                if (artist.isNullOrEmpty()) View.GONE else View.VISIBLE
            )
            val art = if (title.isNullOrEmpty()) null else prefs.getString("art", null)?.let {
                loadArt(context, it)
            }
            if (art != null) {
                views.setImageViewBitmap(R.id.widget_art, art)
            } else {
                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            }

            views.setInt(
                R.id.widget_play_background,
                "setColorFilter",
                prefs.getInt("accent", DEFAULT_ACCENT)
            )
            views.setInt(
                R.id.widget_play_icon,
                "setColorFilter",
                prefs.getInt("onAccent", DEFAULT_ON_ACCENT)
            )
            views.setImageViewResource(
                R.id.widget_play_icon,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
            )
            views.setContentDescription(
                R.id.widget_play,
                if (playing) {
                    label(context, prefs.getString("pause", null), R.string.widget_pause)
                } else {
                    label(context, prefs.getString("play", null), R.string.widget_play)
                }
            )
            views.setContentDescription(
                R.id.widget_next,
                label(context, prefs.getString("next", null), R.string.widget_next)
            )
            views.setContentDescription(
                R.id.widget_previous,
                label(context, prefs.getString("previous", null), R.string.widget_previous)
            )

            val open = PendingIntent.getActivity(
                context,
                0,
                openIntent(context),
                immutable(PendingIntent.FLAG_UPDATE_CURRENT)
            )
            views.setOnClickPendingIntent(R.id.widget_info, open)
            views.setOnClickPendingIntent(
                R.id.widget_play,
                if (live) button(context, if (playing) ACTION_PAUSE else ACTION_PLAY) else open
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                if (live) button(context, ACTION_NEXT) else open
            )
            views.setOnClickPendingIntent(
                R.id.widget_previous,
                if (live) button(context, ACTION_PREVIOUS) else open
            )
            manager.updateAppWidget(ids, views)
        }

        private fun label(context: Context, sent: String?, fallback: Int): String =
            if (sent.isNullOrEmpty()) context.getString(fallback) else sent

        private fun immutable(flags: Int): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags or PendingIntent.FLAG_IMMUTABLE
            } else {
                flags
            }

        /** Riff as from its icon: back to where it was if it's running. */
        private fun openIntent(context: Context): Intent =
            Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)

        private fun button(context: Context, action: String): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                action.hashCode(),
                Intent(context, NowPlayingWidget::class.java).setAction(action),
                immutable(PendingIntent.FLAG_UPDATE_CURRENT)
            )

        /** The art at [path], cut square with the app's small corner radius. */
        private fun loadArt(context: Context, path: String): Bitmap? {
            val density = context.resources.displayMetrics.density
            val size = (ART_DP * density).toInt().coerceIn(48, 256)
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                val side = minOf(bounds.outWidth, bounds.outHeight)
                if (side <= 0) return null
                var sample = 1
                while (side / (sample * 2) >= size) sample *= 2
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                val decoded = BitmapFactory.decodeFile(path, options) ?: return null
                rounded(decoded, size, ART_RADIUS_DP * density)
            } catch (_: Exception) {
                null
            } catch (_: OutOfMemoryError) {
                null
            }
        }

        private fun rounded(source: Bitmap, size: Int, radius: Float): Bitmap {
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val scale = size.toFloat() / minOf(source.width, source.height)
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val matrix = Matrix()
            matrix.setScale(scale, scale)
            matrix.postTranslate(
                (size - source.width * scale) / 2f,
                (size - source.height * scale) / 2f
            )
            shader.setLocalMatrix(matrix)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            paint.shader = shader
            Canvas(out).drawRoundRect(
                RectF(0f, 0f, size.toFloat(), size.toFloat()),
                radius,
                radius,
                paint
            )
            return out
        }
    }
}
