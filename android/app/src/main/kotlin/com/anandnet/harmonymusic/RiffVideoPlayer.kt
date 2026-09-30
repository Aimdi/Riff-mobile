package com.anandnet.harmonymusic

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Video engine for Riff's video mode, built the way NewPipe / WizeStream
 * play YouTube: one ExoPlayer merges the video-only stream with the audio
 * stream ([MergingMediaSource]), so A/V sync, buffering and seeking are the
 * player's job. Frames go to a Flutter texture; Dart drives it over
 * `riff/video` and listens on `riff/video/events`.
 */
@OptIn(markerClass = [UnstableApi::class])
class RiffVideoPlayer(
    private val context: Context,
    private val textures: TextureRegistry,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, Player.Listener {

    private val methods = MethodChannel(messenger, "riff/video")
    private val events = EventChannel(messenger, "riff/video/events")
    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var player: ExoPlayer? = null
    private var texture: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null

    private val ticker = object : Runnable {
        override fun run() {
            emitPosition()
            if (player?.isPlaying == true) main.postDelayed(this, TICK_MS)
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> result.success(ensurePlayer())
                "load" -> {
                    val videoUrl = call.argument<String>("videoUrl")
                    if (videoUrl.isNullOrEmpty()) {
                        result.error("ARG", "videoUrl missing", null)
                        return
                    }
                    load(
                        videoUrl,
                        call.argument<String>("audioUrl"),
                        (call.argument<Number>("startMs") ?: 0).toLong(),
                        call.argument<Boolean>("play") ?: false,
                        (call.argument<Number>("speed") ?: 1.0).toFloat(),
                    )
                    result.success(true)
                }
                "play" -> { player?.play(); result.success(null) }
                "pause" -> { player?.pause(); result.success(null) }
                "seekTo" -> {
                    player?.seekTo((call.argument<Number>("positionMs") ?: 0).toLong())
                    emitPosition()
                    result.success(null)
                }
                "setSpeed" -> {
                    val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
                    player?.playbackParameters = PlaybackParameters(speed.coerceIn(0.25f, 4f))
                    result.success(null)
                }
                "stop" -> {
                    player?.stop()
                    player?.clearMediaItems()
                    result.success(null)
                }
                "dispose" -> { release(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("VIDEO", e.toString(), null)
        }
    }

    /** Creates the player + texture once; returns the Flutter texture id. */
    private fun ensurePlayer(): Long {
        texture?.let { return it.id() }
        val entry = textures.createSurfaceTexture()
        texture = entry
        surface = Surface(entry.surfaceTexture())
        val exo = ExoPlayer.Builder(context)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                /* handleAudioFocus= */ true,
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
        exo.setVideoSurface(surface)
        exo.addListener(this)
        player = exo
        return entry.id()
    }

    private fun load(
        videoUrl: String,
        audioUrl: String?,
        startMs: Long,
        play: Boolean,
        speed: Float,
    ) {
        ensurePlayer()
        val exo = player ?: return
        val factory = ProgressiveMediaSource.Factory(YoutubeDataSource.Factory())
        val video = factory.createMediaSource(MediaItem.fromUri(videoUrl))
        val source: MediaSource = if (audioUrl.isNullOrEmpty()) {
            video
        } else {
            MergingMediaSource(
                /* adjustPeriodTimeOffsets= */ true,
                video,
                factory.createMediaSource(MediaItem.fromUri(audioUrl)),
            )
        }
        exo.setMediaSource(source, startMs.coerceAtLeast(0))
        exo.playbackParameters = PlaybackParameters(speed.coerceIn(0.25f, 4f))
        exo.playWhenReady = play
        exo.prepare()
    }

    private fun release() {
        main.removeCallbacks(ticker)
        player?.removeListener(this)
        player?.release()
        player = null
        surface?.release()
        surface = null
        texture?.release()
        texture = null
    }

    fun dispose() {
        release()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    // --- events --------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        sink?.success(event)
    }

    private fun emitPosition() {
        val exo = player ?: return
        val duration = exo.duration
        emit(
            mapOf(
                "event" to "position",
                "positionMs" to exo.currentPosition,
                "bufferedMs" to exo.bufferedPosition,
                "durationMs" to if (duration == C.TIME_UNSET) -1L else duration,
            )
        )
    }

    private fun emitState() {
        val exo = player ?: return
        emit(
            mapOf(
                "event" to "state",
                "playing" to exo.isPlaying,
                "buffering" to (exo.playbackState == Player.STATE_BUFFERING),
                "ended" to (exo.playbackState == Player.STATE_ENDED),
                "ready" to (exo.playbackState == Player.STATE_READY),
            )
        )
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        emitState()
        main.removeCallbacks(ticker)
        if (isPlaying) main.post(ticker) else emitPosition()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        emitState()
        emitPosition()
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (videoSize.width <= 0 || videoSize.height <= 0) return
        texture?.surfaceTexture()?.setDefaultBufferSize(videoSize.width, videoSize.height)
        emit(
            mapOf(
                "event" to "size",
                "width" to videoSize.width,
                "height" to videoSize.height,
                "pixelRatio" to videoSize.pixelWidthHeightRatio.toDouble(),
            )
        )
    }

    override fun onPlayerError(error: PlaybackException) {
        emit(
            mapOf(
                "event" to "error",
                "code" to error.errorCodeName,
                "message" to (error.cause?.message ?: error.message ?: ""),
            )
        )
    }

    companion object {
        private const val TICK_MS = 250L
    }
}
