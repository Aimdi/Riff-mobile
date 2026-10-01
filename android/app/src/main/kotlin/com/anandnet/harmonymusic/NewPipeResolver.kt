package com.anandnet.harmonymusic

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
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

    /**
     * Optional YouTube session cookie (SAPISID…) from in-app login and the
     * matching `Authorization: SAPISIDHASH …` header. Per thread: requests
     * resolve in parallel and one must not pick up another's session.
     * NewPipe downloads on the thread that calls [StreamInfo.getInfo].
     */
    private class Auth(val cookie: String?, val header: String?)

    private val auth = ThreadLocal<Auth?>()

    /** Sets the session used by resolutions on the calling thread. */
    @JvmStatic
    fun setAuth(cookie: String?, authorization: String?) {
        auth.set(Auth(cookie?.takeIf { it.isNotBlank() },
            authorization?.takeIf { it.isNotBlank() }))
    }

    // --- StreamInfo cache ----------------------------------------------
    // getAudioStreams / getMuxedVideoStreams / getVideoStreams all need the
    // same extraction; toggling video mode right after the audio resolve
    // (or a prefetch followed by the real play) reuses it.

    private const val CACHE_TTL_MS = 5 * 60 * 1000L
    private const val CACHE_MAX = 20

    private class Cached(val info: StreamInfo, val atMs: Long)

    private val cache = object : LinkedHashMap<String, Cached>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Cached>?) =
            size > CACHE_MAX
    }

    /** Drops cached extractions (e.g. after sign-out / cookies cleared). */
    @JvmStatic
    fun clearCache() {
        synchronized(cache) { cache.clear() }
    }

    private fun streamInfo(videoId: String): StreamInfo {
        ensureInit()
        synchronized(cache) {
            val hit = cache[videoId]
            if (hit != null) {
                if (System.currentTimeMillis() - hit.atMs < CACHE_TTL_MS) return hit.info
                cache.remove(videoId)
            }
        }
        val info = StreamInfo.getInfo(
            ServiceList.YouTube, "https://www.youtube.com/watch?v=$videoId")
        // Don't cache a failed / partial extraction.
        if (info.audioStreams.isNotEmpty()) {
            synchronized(cache) {
                cache[videoId] = Cached(info, System.currentTimeMillis())
            }
        }
        return info
    }

    private class SimpleDownloader : Downloader() {
        override fun execute(request: Request): Response {
            val conn = URL(request.url()).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 20000
            conn.requestMethod = request.httpMethod()
            conn.instanceFollowRedirects = true
            try {
                val cookies = mutableListOf<String>()
                for ((name, values) in request.headers()) {
                    if (name.equals("Cookie", ignoreCase = true)) {
                        cookies += values
                        continue
                    }
                    for (value in values) conn.addRequestProperty(name, value)
                }
                if (conn.getRequestProperty("User-Agent") == null) {
                    conn.setRequestProperty("User-Agent", USER_AGENT)
                }
                // Prefer the signed-in session when available — anonymous
                // player responses increasingly return LOGIN_REQUIRED / bot
                // checks. Appended to NewPipe's own cookies (e.g. consent),
                // not dropped because of them.
                val session = auth.get()
                session?.cookie?.let { cookies += it }
                val cookieHeader = cookies.filter { it.isNotBlank() }.joinToString("; ")
                if (cookieHeader.isNotEmpty()) conn.setRequestProperty("Cookie", cookieHeader)
                val authorization = session?.header
                if (authorization != null && conn.getRequestProperty("Authorization") == null) {
                    conn.setRequestProperty("Authorization", authorization)
                    conn.setRequestProperty("X-Origin", "https://www.youtube.com")
                }
                request.dataToSend()?.let { data ->
                    conn.doOutput = true
                    conn.outputStream.use { it.write(data) }
                }
                val code = conn.responseCode
                if (code == 429) {
                    // Same as NewPipe's own downloader: YouTube rate-limits /
                    // wants a captcha. Callers treat it as a bot check and
                    // retry signed in.
                    try { conn.errorStream?.close() } catch (_: Exception) {}
                    conn.disconnect()
                    throw ReCaptchaException("reCaptcha Challenge requested", request.url())
                }
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                val body = stream?.bufferedReader()?.use { it.readText() } ?: ""
                if (stream == null) conn.disconnect()
                val headers = conn.headerFields.filterKeys { it != null }
                return Response(code, conn.responseMessage ?: "", headers, body,
                    conn.url.toString())
            } catch (e: Exception) {
                // Fully read + closed bodies go back to the keep-alive pool;
                // anything that failed half-way is dropped.
                conn.disconnect()
                throw e
            }
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
        val info = streamInfo(videoId)
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
        val info = streamInfo(videoId)
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

    /**
     * Returns video-only streams for [videoId] (video mode pairs one of
     * these with an audio-only stream inside a single mpv instance, so
     * A/V sync is the engine's job). Each map: itag, mimeType, height,
     * fps, url, size (bytes), durationMs.
     */
    @JvmStatic
    fun getVideoStreams(videoId: String): List<Map<String, Any?>> {
        val info = streamInfo(videoId)
        if (info.videoOnlyStreams.isEmpty()) {
            println("NewPipeResolver: no video-only streams for $videoId; " +
                "errors=${info.errors}")
        }
        val durationMs = info.duration * 1000
        return info.videoOnlyStreams
            .filter { it.isUrl && !it.content.isNullOrEmpty() }
            .map { s ->
                mapOf(
                    "itag" to (s.itagItem?.id ?: -1),
                    "mimeType" to (s.format?.mimeType ?: ""),
                    "height" to s.height,
                    "fps" to s.fps,
                    "url" to s.content,
                    "size" to (s.itagItem?.contentLength ?: 0L),
                    "durationMs" to durationMs,
                )
            }
    }
}
