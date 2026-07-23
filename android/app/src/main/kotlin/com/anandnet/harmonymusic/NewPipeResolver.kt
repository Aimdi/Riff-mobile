package com.anandnet.harmonymusic

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.VideoStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Audio/video stream resolution via NewPipeExtractor - the same engine RiPlay
 * (and NewPipe itself) uses. It keeps up with YouTube's JS player,
 * signature deciphering and throttling parameters, which pure InnerTube
 * clients regularly break on.
 *
 * Pure JVM (no Android imports) so it can run as a plain unit test.
 */
object NewPipeResolver {

    private const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

    @Volatile
    private var initialized = false

    /** Optional YouTube session cookie (SAPISID…) from in-app login. */
    @Volatile
    private var authCookie: String? = null

    /** Optional Authorization: SAPISIDHASH … header. */
    @Volatile
    private var authHeader: String? = null

    @JvmStatic
    fun setAuth(cookie: String?, authorization: String?) {
        authCookie = cookie?.takeIf { it.isNotBlank() }
        authHeader = authorization?.takeIf { it.isNotBlank() }
    }

    private class SimpleDownloader : Downloader() {
        override fun execute(request: Request): Response {
            val conn = URL(request.url()).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 20000
            conn.requestMethod = request.httpMethod()
            conn.instanceFollowRedirects = true
            for ((name, values) in request.headers()) {
                for (value in values) conn.addRequestProperty(name, value)
            }
            if (conn.getRequestProperty("User-Agent") == null) {
                conn.setRequestProperty("User-Agent", USER_AGENT)
            }
            // Prefer the signed-in session when available — anonymous player
            // responses increasingly return LOGIN_REQUIRED / bot checks.
            val cookie = authCookie
            if (cookie != null && conn.getRequestProperty("Cookie") == null) {
                conn.setRequestProperty("Cookie", cookie)
            }
            val auth = authHeader
            if (auth != null && conn.getRequestProperty("Authorization") == null) {
                conn.setRequestProperty("Authorization", auth)
                conn.setRequestProperty("X-Origin", "https://www.youtube.com")
            }
            request.dataToSend()?.let { data ->
                conn.doOutput = true
                conn.outputStream.use { it.write(data) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
            val headers = conn.headerFields.filterKeys { it != null }
            return Response(code, conn.responseMessage ?: "", headers, body,
                conn.url.toString())
        }
    }

    private fun ensureInit() {
        if (!initialized) {
            synchronized(this) {
                if (!initialized) {
                    NewPipe.init(SimpleDownloader())
                    initialized = true
                }
            }
        }
    }

    /**
     * Returns audio-only streams for [videoId] with directly playable
     * (deciphered, throttling-solved) urls. Each map: itag, mimeType,
     * bitrate (bits/s), url, size (bytes), durationMs.
     */
    @JvmStatic
    fun getAudioStreams(videoId: String): List<Map<String, Any?>> {
        ensureInit()
        val info = StreamInfo.getInfo(
            ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        if (info.audioStreams.isEmpty()) {
            // Surface why (non-fatal extraction errors are collected here).
            println("NewPipeResolver: no audio streams for $videoId; " +
                "errors=${info.errors}")
        }
        val durationMs = info.duration * 1000
        return info.audioStreams
            .filter { it.isUrl && !it.content.isNullOrEmpty() }
            .map { s ->
                mapOf(
                    "itag" to (s.itagItem?.id ?: -1),
                    "mimeType" to (s.format?.mimeType ?: ""),
                    "bitrate" to (if (s.averageBitrate > 0) s.averageBitrate * 1000 else 0),
                    "url" to s.content,
                    "size" to (s.itagItem?.contentLength ?: 0L),
                    "durationMs" to durationMs,
                )
            }
    }

    /**
     * Player video streams: muxed + video-only.
     * Each map: itag, mimeType, width, height, url, size, durationMs, hasAudio.
     * Video-only is preferred by the Dart picker so muted playback does not
     * decode a discarded audio track.
     */
    @JvmStatic
    fun getMuxedVideoStreams(videoId: String): List<Map<String, Any?>> {
        ensureInit()
        val info = StreamInfo.getInfo(
            ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        val durationMs = info.duration * 1000
        fun mapStream(s: VideoStream, hasAudio: Boolean): Map<String, Any?> =
            mapOf(
                "itag" to (s.itagItem?.id ?: -1),
                "mimeType" to (s.format?.mimeType ?: ""),
                "width" to s.width,
                "height" to s.height,
                "url" to s.content,
                "size" to (s.itagItem?.contentLength ?: 0L),
                "durationMs" to durationMs,
                "hasAudio" to hasAudio,
            )
        val muxed = info.videoStreams
            .filter { it.isUrl && !it.content.isNullOrEmpty() }
            .map { mapStream(it, true) }
        val videoOnly = info.videoOnlyStreams
            .filter { it.isUrl && !it.content.isNullOrEmpty() }
            .map { mapStream(it, false) }
        return muxed + videoOnly
    }
}
