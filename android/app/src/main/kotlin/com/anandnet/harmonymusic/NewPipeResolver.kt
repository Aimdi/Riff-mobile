package com.anandnet.harmonymusic

import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.net.HttpURLConnection
import java.net.URL

/**
 * Audio stream resolution via NewPipeExtractor - the same engine RiPlay
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
}
