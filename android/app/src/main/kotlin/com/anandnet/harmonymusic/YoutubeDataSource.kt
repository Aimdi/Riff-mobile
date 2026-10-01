package com.anandnet.harmonymusic

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * HTTP data source for YouTube `videoplayback` streams, following the rules
 * NewPipe / WizeStream use (see WizeStream's YoutubeHttpDataSource, GPL-3.0):
 * a POST with the `x\0` body, an incrementing `rn` request number, and the
 * User-Agent of the client the stream url was issued to.
 *
 * On top of that, ranges are fetched in [CHUNK_BYTES] pieces. One unbounded
 * range over a multi-hour podcast is what YouTube throttles or cuts off
 * (HTTP 403 part-way through); chunked requests keep long videos flowing.
 * Chunking is invisible to ExoPlayer: [read] opens the next chunk itself.
 */
@OptIn(markerClass = [UnstableApi::class])
class YoutubeDataSource private constructor() : BaseDataSource(/* isNetwork= */ true) {

    class Factory : DataSource.Factory {
        override fun createDataSource(): DataSource = YoutubeDataSource()
    }

    private var dataSpec: DataSpec? = null
    private var connection: HttpURLConnection? = null
    private var input: InputStream? = null
    private var opened = false

    /** Absolute offset of the next byte [read] returns. */
    private var position = 0L

    /** Absolute offset one past the last byte to return, or unknown. */
    private var end = C.LENGTH_UNSET.toLong()

    /** Absolute offset one past the last byte of the open chunk. */
    private var chunkEnd = 0L
    private var requestNumber = 0L
    private var earlyEnds = 0

    /**
     * Where the redirector sent the first chunk (without our `rn`), so later
     * chunks of the same open() go straight to the media server.
     */
    private var resolvedUrl: String? = null

    override fun open(dataSpec: DataSpec): Long {
        this.dataSpec = dataSpec
        resolvedUrl = null
        earlyEnds = 0
        transferInitializing(dataSpec)
        position = dataSpec.position
        end = if (dataSpec.length != C.LENGTH_UNSET.toLong()) {
            dataSpec.position + dataSpec.length
        } else {
            C.LENGTH_UNSET.toLong()
        }
        val total = openChunk(dataSpec.uri)
        if (end == C.LENGTH_UNSET.toLong() && total > 0) end = total
        opened = true
        transferStarted(dataSpec)
        return if (end == C.LENGTH_UNSET.toLong()) {
            C.LENGTH_UNSET.toLong()
        } else {
            end - position
        }
    }

    /**
     * Requests `[position, position + CHUNK_BYTES)` (clipped to [end]).
     * Returns the full resource size when the server reports it, else -1.
     */
    private fun openChunk(uri: Uri): Long {
        closeConnection()
        var chunkLast = position + CHUNK_BYTES - 1
        if (end != C.LENGTH_UNSET.toLong()) chunkLast = minOf(chunkLast, end - 1)

        var url = resolvedUrl ?: uri.toString()
        val addedRn = isVideoPlayback(url) && !url.contains(RN_PARAMETER)
        if (addedRn) url += RN_PARAMETER + requestNumber++

        var redirects = 0
        while (true) {
            val isVideoPlayback = isVideoPlayback(url)
            // A non-http(s) url (e.g. a local file) is a playback error,
            // not a ClassCastException.
            val conn = (URL(url).openConnection() as? HttpURLConnection
                ?: throw IOException("Not an HTTP url")).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = false
                setRequestProperty("Range", "bytes=$position-$chunkLast")
                setRequestProperty("Accept-Encoding", "identity")
                setRequestProperty("User-Agent", userAgentFor(url))
                if (isWebClient(url)) {
                    setRequestProperty("Origin", YOUTUBE_ORIGIN)
                    setRequestProperty("Referer", "$YOUTUBE_ORIGIN/")
                    setRequestProperty("Sec-Fetch-Dest", "empty")
                    setRequestProperty("Sec-Fetch-Mode", "cors")
                    setRequestProperty("Sec-Fetch-Site", "cross-site")
                }
            }
            if (isVideoPlayback) {
                // Most YouTube clients fetch media with a POST and this body.
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setFixedLengthStreamingMode(POST_BODY.size)
                conn.outputStream.use { it.write(POST_BODY) }
            }
            val code = conn.responseCode
            if (code in 300..399 && redirects < MAX_REDIRECTS) {
                val location = conn.getHeaderField("Location")
                conn.disconnect()
                if (location.isNullOrEmpty()) throw IOException("Redirect without Location")
                url = URL(URL(url), location).toString()
                redirects++
                continue
            }
            if (code == 416 && end == C.LENGTH_UNSET.toLong() && position > 0) {
                // Length unknown and the previous chunk ended exactly at the
                // end of the resource: nothing left to read.
                conn.disconnect()
                end = position
                chunkEnd = position
                return -1L
            }
            if (code !in 200..299) {
                val message = conn.responseMessage
                val headers = conn.headerFields
                conn.disconnect()
                // Typed so ExoPlayer reports ERROR_CODE_IO_BAD_HTTP_STATUS.
                throw HttpDataSource.InvalidResponseCodeException(
                    code, message, null, headers, dataSpec!!, ByteArray(0))
            }
            if (redirects > 0) {
                resolvedUrl = if (addedRn) removeQueryParam(url, "rn") else url
            }
            connection = conn
            input = conn.inputStream
            if (code == 200 && position > 0) {
                // Server ignored the range: skip to where we were asked to start.
                skipFully(input!!, position)
            }
            val contentLength =
                conn.getHeaderField("Content-Length")?.trim()?.toLongOrNull() ?: -1L
            chunkEnd = if (code == 206) {
                // The server may return less than asked (end of resource).
                (lastFromContentRange(conn.getHeaderField("Content-Range"))
                    ?: chunkLast) + 1
            } else {
                if (contentLength > 0) contentLength else Long.MAX_VALUE
            }
            return totalFromContentRange(conn.getHeaderField("Content-Range"))
                ?: if (code == 200) contentLength else -1L
        }
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (end != C.LENGTH_UNSET.toLong() && position >= end) return C.RESULT_END_OF_INPUT
        if (position >= chunkEnd) {
            // Chunk done but the resource continues: fetch the next piece.
            openChunk(dataSpec!!.uri)
            if (end != C.LENGTH_UNSET.toLong() && position >= end) return C.RESULT_END_OF_INPUT
        }
        var toRead = length.toLong()
        if (end != C.LENGTH_UNSET.toLong()) toRead = minOf(toRead, end - position)
        toRead = minOf(toRead, chunkEnd - position)
        val n = input?.read(buffer, offset, toRead.toInt()) ?: -1
        if (n == -1) {
            if (end != C.LENGTH_UNSET.toLong() && position >= end) return C.RESULT_END_OF_INPUT
            // Length unknown and the server sent the whole resource (no
            // range, no Content-Length): this is the real end.
            if (end == C.LENGTH_UNSET.toLong() && chunkEnd == Long.MAX_VALUE) {
                return C.RESULT_END_OF_INPUT
            }
            // Connection ended before the chunk did: resume from the same
            // offset (also when the total length is unknown).
            if (++earlyEnds > MAX_EARLY_ENDS) throw IOException("YouTube stream kept ending early")
            chunkEnd = position
            return read(buffer, offset, length)
        }
        earlyEnds = 0
        position += n
        bytesTransferred(n)
        return n
    }

    override fun getUri(): Uri? = dataSpec?.uri

    override fun close() {
        closeConnection()
        if (opened) {
            opened = false
            transferEnded()
        }
        dataSpec = null
    }

    private fun closeConnection() {
        try {
            input?.close()
        } catch (_: IOException) {
        }
        input = null
        connection?.disconnect()
        connection = null
    }

    companion object {
        /** yt-dlp uses the same 10 MB chunk size for YouTube. */
        private const val CHUNK_BYTES = 10L * 1024 * 1024
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 20_000
        private const val MAX_REDIRECTS = 5
        private const val MAX_EARLY_ENDS = 3
        private const val RN_PARAMETER = "&rn="
        private val POST_BODY = byteArrayOf(0x78, 0)
        private const val YOUTUBE_ORIGIN = "https://www.youtube.com"
        private const val DESKTOP_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

        private fun isVideoPlayback(url: String): Boolean =
            try {
                URL(url).path.startsWith("/videoplayback")
            } catch (_: Exception) {
                false
            }

        internal fun queryParam(url: String, name: String): String? {
            val query = try {
                URL(url).query
            } catch (_: Exception) {
                null
            } ?: return null
            for (part in query.split('&')) {
                val eq = part.indexOf('=')
                val key = if (eq < 0) part else part.substring(0, eq)
                if (key == name) {
                    return if (eq < 0) "" else java.net.URLDecoder.decode(part.substring(eq + 1), "UTF-8")
                }
            }
            return null
        }

        private fun isWebClient(url: String): Boolean {
            val client = queryParam(url, "c") ?: return true
            return client.startsWith("WEB") || client.startsWith("MWEB") ||
                client.startsWith("TVHTML5")
        }

        /** Match the client (`c`) and version (`cver`) the url was issued to. */
        internal fun userAgentFor(url: String): String {
            val client = queryParam(url, "c") ?: return DESKTOP_USER_AGENT
            val version = queryParam(url, "cver") ?: ""
            return when {
                client == "ANDROID_VR" ->
                    "com.google.android.apps.youtube.vr.oculus/$version " +
                        "(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
                client.startsWith("ANDROID") ->
                    "com.google.android.youtube/$version (Linux; U; Android 14) gzip"
                client.startsWith("IOS") ->
                    "com.google.ios.youtube/$version " +
                        "(iPhone16,2; U; CPU iOS 18_1_0 like Mac OS X;)"
                else -> DESKTOP_USER_AGENT
            }
        }

        /** "bytes 0-99/12345" → 99 (inclusive last byte). */
        internal fun lastFromContentRange(header: String?): Long? {
            val range = header?.trim()?.substringAfter(' ', "")?.substringBefore('/') ?: return null
            return range.substringAfter('-', "").trim().toLongOrNull()
        }

        /** Drops every `name=` parameter from [url]'s query. */
        internal fun removeQueryParam(url: String, name: String): String {
            val q = url.indexOf('?')
            if (q < 0) return url
            val kept = url.substring(q + 1).split('&').filter {
                it.isNotEmpty() && it.substringBefore('=') != name
            }
            return url.substring(0, q) + if (kept.isEmpty()) "" else "?" + kept.joinToString("&")
        }

        /** "bytes 0-99/12345" → 12345. */
        internal fun totalFromContentRange(header: String?): Long? {
            val total = header?.substringAfterLast('/', "")?.trim() ?: return null
            return total.toLongOrNull()
        }

        private fun skipFully(stream: InputStream, bytes: Long) {
            var left = bytes
            val scratch = ByteArray(8192)
            while (left > 0) {
                val n = stream.read(scratch, 0, minOf(scratch.size.toLong(), left).toInt())
                if (n == -1) throw IOException("Stream ended while skipping")
                left -= n
            }
        }
    }
}
