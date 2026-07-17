package com.anandnet.harmonymusic

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Runs on the JVM with real network access (CI runners): verifies
 * NewPipeExtractor resolves playable audio stream urls end-to-end.
 */
class NewPipeResolverTest {

    @Test
    fun resolvesAudioStreams() {
        val streams = NewPipeResolver.getAudioStreams("dQw4w9WgXcQ")
        println("NEWPIPE STREAMS: " +
            streams.map { "${it["itag"]} ${it["mimeType"]} ${it["bitrate"]}bps" })
        assertTrue("no audio streams resolved", streams.isNotEmpty())
        assertTrue("stream urls must be https",
            streams.all { (it["url"] as String).startsWith("https://") })
    }
}
