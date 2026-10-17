package com.anandnet.harmonymusic

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Xml
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * "riff/episode_alerts": new-episode notifications for the shows followed
 * (lib/services/new_episode_alerts.dart), as Pocket Casts, AntennaPod and
 * Apple Podcasts send them. Every few hours, with Riff closed too, a job
 * ([NewEpisodesJob]) reads the start of each show's feed and posts a
 * notification for a show with episodes it hadn't seen there before; the
 * first look at a show only notes what's there. A feed unchanged since
 * the last look (ETag / Last-Modified) isn't read again. Needs no
 * activity, like riff/downloads.
 */
object EpisodeAlerts : MethodChannel.MethodCallHandler {
    /** Set by MainActivity. */
    var appContext: Context? = null

    private const val PREFS = "riff_episode_alerts"
    private const val KEY_SHOWS = "shows"
    private const val KEY_CHANNEL = "channel"
    private const val KEY_COUNT = "count"

    // Kept per feed address.
    private const val KEY_SEEN = "seen:"
    private const val KEY_ETAG = "etag:"
    private const val KEY_MODIFIED = "modified:"
    private const val KEY_MOVED = "moved:"
    private val PER_FEED = listOf(KEY_SEEN, KEY_ETAG, KEY_MODIFIED, KEY_MOVED)

    private const val PERIODIC_JOB = 7303
    private const val FIRST_LOOK_JOB = 7304
    private const val INTERVAL_MS = 4 * 60 * 60 * 1000L

    private const val CHANNEL_ID = "riff_new_episodes"
    private const val NOTIFICATION_TAG = "riff_new_episodes"

    /** lib/services/new_episode_alerts.dart: the Podcasts Inbox. */
    private const val INBOX_LINK = "riff://podcasts/inbox"
    private const val USER_AGENT = "Riff/1.0 (podcast)"
    private const val TIMEOUT_MS = 20_000
    private const val MAX_REDIRECTS = 5

    /** Episodes read at the start of a feed (the newest, in nearly all). */
    private const val HEAD_ITEMS = 5

    /** Episode keys kept per show. */
    private const val SEEN_MAX = 50

    /**
     * Older episodes it hadn't seen aren't news (a feed that changed its
     * episodes' ids, a phone off for weeks).
     */
    private const val NEW_FOR_MS = 7 * 24 * 60 * 60 * 1000L

    private const val ART_SIZE = 256
    private const val ART_MAX_BYTES = 3 * 1024 * 1024
    private const val RELAXED = "http://xmlpull.org/v1/doc/features.html#relaxed"

    // HTML's, which XML doesn't know, as titles have them.
    private val HTML_ENTITIES = mapOf(
        "nbsp" to "\u00A0",
        "ndash" to "\u2013",
        "mdash" to "\u2014",
        "hellip" to "\u2026",
        "lsquo" to "\u2018",
        "rsquo" to "\u2019",
        "ldquo" to "\u201C",
        "rdquo" to "\u201D",
    )

    // RSS dates (RFC 822), as feeds write them.
    private val DATE_FORMATS = listOf(
        "EEE, d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss z",
        "EEE, d MMM yyyy HH:mm Z",
        "EEE, d MMM yyyy HH:mm z",
        "d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss z",
    )

    private class Show(val feed: String, val title: String, val art: String)

    private class Episode(val key: String, val title: String, val published: Long?)

    /** A feed's first episodes, and the address it says it moved to. */
    private class FeedHead(val episodes: List<Episode>, val movedTo: String?)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.success(false)
            return
        }
        when (call.method) {
            "set" -> result.success(
                set(
                    context,
                    call.argument<Boolean>("on") ?: false,
                    call.argument<List<Map<String, Any?>>>("shows") ?: emptyList(),
                    call.argument<String>("channel") ?: "",
                    call.argument<String>("count") ?: "",
                )
            )
            else -> result.notImplemented()
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * On: the shows to look at ({feed, title, art}) and the notification's
     * words in the app's language; the job is scheduled if it isn't. Off:
     * the job goes, and so does all it noted, so switched on again it
     * doesn't bring the time it was off all at once.
     */
    private fun set(
        context: Context,
        on: Boolean,
        shows: List<Map<String, Any?>>,
        channelName: String,
        countLabel: String,
    ): Boolean {
        val prefs = prefs(context)
        val scheduler =
            context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
                ?: return false
        if (!on) {
            scheduler.cancel(PERIODIC_JOB)
            scheduler.cancel(FIRST_LOOK_JOB)
            prefs.edit().clear().apply()
            return true
        }
        val before = shows(prefs).map { it.feed }.toSet()
        val list = JSONArray()
        val feeds = HashSet<String>()
        for (show in shows) {
            val feed = show["feed"] as? String ?: continue
            if (webAddress(feed) == null || !feeds.add(feed)) continue
            list.put(
                JSONObject()
                    .put("feed", feed)
                    .put("title", show["title"] as? String ?: "")
                    .put("art", show["art"] as? String ?: "")
            )
        }
        // What's noted for shows no longer followed goes (a moved show's
        // new address stays with it).
        val kept = HashSet<String>(feeds)
        for (feed in feeds) prefs.getString(KEY_MOVED + feed, null)?.let { kept.add(it) }
        val editor = prefs.edit()
            .putString(KEY_SHOWS, list.toString())
            .putString(KEY_CHANNEL, channelName)
            .putString(KEY_COUNT, countLabel)
        for (key in prefs.all.keys) {
            val feed = PER_FEED.firstOrNull { key.startsWith(it) }?.let { key.removePrefix(it) }
            if (feed != null && feed !in kept) editor.remove(key)
        }
        editor.apply()
        val job = ComponentName(context, NewEpisodesJob::class.java)
        return try {
            val pending = scheduler.allPendingJobs.firstOrNull { it.id == PERIODIC_JOB }
            // Not scheduled again when it is: that would put its next look
            // off by a whole interval each time Riff opens.
            if (pending == null || pending.intervalMillis != INTERVAL_MS) {
                val periodic = JobInfo.Builder(PERIODIC_JOB, job)
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPeriodic(INTERVAL_MS)
                    .setPersisted(true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    periodic.setRequiresBatteryNotLow(true)
                }
                scheduler.schedule(periodic.build())
            }
            // A show just followed is looked at now, so an episode it puts
            // out before the next look is news. (Once: a feed that can't
            // be read waits for the next look.)
            if (feeds.any { it !in before && !prefs.contains(KEY_SEEN + it) }) {
                scheduler.schedule(
                    JobInfo.Builder(FIRST_LOOK_JOB, job)
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                        .build()
                )
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** One look at every show followed; [stopped] says when to stop. */
    @Synchronized
    fun check(context: Context, stopped: () -> Boolean) {
        val prefs = prefs(context)
        val news = System.currentTimeMillis() - NEW_FOR_MS
        for (show in shows(prefs)) {
            if (stopped()) return
            val episodes = latest(show.feed, prefs) ?: continue
            if (episodes.isEmpty()) continue
            val noted = prefs.getString(KEY_SEEN + show.feed, null)
            val seen = noted?.let { keys(it) } ?: emptyList<String>()
            val fresh = if (noted == null) emptyList<Episode>() else episodes.filter {
                it.key !in seen && (it.published == null || it.published >= news)
            }
            val remembered = LinkedHashSet<String>()
            for (episode in episodes) remembered.add(episode.key)
            for (key in seen) if (remembered.size < SEEN_MAX) remembered.add(key)
            prefs.edit()
                .putString(KEY_SEEN + show.feed, JSONArray(remembered.toList()).toString())
                .apply()
            if (fresh.isNotEmpty()) {
                try {
                    notify(context, prefs, show, fresh)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun shows(prefs: SharedPreferences): List<Show> = try {
        val list = JSONArray(prefs.getString(KEY_SHOWS, null) ?: "[]")
        (0 until list.length()).mapNotNull { i ->
            val show = list.optJSONObject(i) ?: return@mapNotNull null
            val feed = show.optString("feed")
            if (feed.isEmpty()) null
            else Show(feed, show.optString("title"), show.optString("art"))
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun keys(raw: String): List<String> = try {
        val list = JSONArray(raw)
        (0 until list.length()).map { list.optString(it) }
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * The first episodes of [feed], or of the feed it moved to (as the app
     * follows itunes:new-feed-url); null when unchanged since the last look
     * or unreadable.
     */
    private fun latest(feed: String, prefs: SharedPreferences): List<Episode>? {
        val address = prefs.getString(KEY_MOVED + feed, null) ?: feed
        val head = read(address, prefs) ?: return null
        val movedTo = head.movedTo
        if (movedTo != null && movedTo != address) {
            val moved = read(movedTo, prefs)
            if (moved != null && moved.episodes.isNotEmpty()) {
                prefs.edit().putString(KEY_MOVED + feed, movedTo).apply()
                return moved.episodes
            }
        }
        return head.episodes
    }

    private fun read(address: String, prefs: SharedPreferences): FeedHead? {
        val connection = try {
            open(
                address,
                prefs.getString(KEY_ETAG + address, null),
                prefs.getString(KEY_MODIFIED + address, null),
            )
        } catch (_: Exception) {
            null
        } ?: return null
        return try {
            val head = connection.inputStream.use { parse(it) }
            val editor = prefs.edit()
            val etag = connection.getHeaderField("ETag")
            val modified = connection.getHeaderField("Last-Modified")
            if (etag.isNullOrEmpty()) editor.remove(KEY_ETAG + address)
            else editor.putString(KEY_ETAG + address, etag)
            if (modified.isNullOrEmpty()) editor.remove(KEY_MODIFIED + address)
            else editor.putString(KEY_MODIFIED + address, modified)
            editor.apply()
            head
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    /**
     * [address] answered with 200, following redirects (http to https
     * too, which HttpURLConnection won't); null for anything else, 304 Not
     * Modified included.
     */
    private fun open(
        address: String,
        etag: String? = null,
        modified: String? = null,
    ): HttpURLConnection? {
        var url = URL(address)
        repeat(MAX_REDIRECTS) {
            val connection = url.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("User-Agent", USER_AGENT)
            if (etag != null) connection.setRequestProperty("If-None-Match", etag)
            if (modified != null) connection.setRequestProperty("If-Modified-Since", modified)
            val code = try {
                connection.responseCode
            } catch (_: Exception) {
                connection.disconnect()
                return null
            }
            when (code) {
                HttpURLConnection.HTTP_OK -> return connection
                HttpURLConnection.HTTP_MOVED_PERM,
                HttpURLConnection.HTTP_MOVED_TEMP,
                HttpURLConnection.HTTP_SEE_OTHER,
                307,
                308 -> {
                    val location = connection.getHeaderField("Location")
                    connection.disconnect()
                    if (location.isNullOrEmpty()) return null
                    url = URL(url, location)
                    if (url.protocol != "http" && url.protocol != "https") return null
                }
                else -> {
                    connection.disconnect()
                    return null
                }
            }
        }
        return null
    }

    /** The first [HEAD_ITEMS] episodes; the rest of the feed isn't read. */
    private fun parse(stream: InputStream): FeedHead {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        try {
            // Feeds that aren't quite XML still read.
            parser.setFeature(RELAXED, true)
        } catch (_: Exception) {
        }
        parser.setInput(stream, null)
        for ((name, text) in HTML_ENTITIES) {
            try {
                parser.defineEntityReplacementText(name, text)
            } catch (_: Exception) {
            }
        }
        val episodes = ArrayList<Episode>()
        var movedTo: String? = null
        var inItem = false
        var title = ""
        var guid = ""
        var enclosure = ""
        var date = ""
        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT && episodes.size < HEAD_ITEMS) {
            if (event == XmlPullParser.START_TAG) {
                when (parser.name) {
                    "item" -> {
                        inItem = true
                        title = ""
                        guid = ""
                        enclosure = ""
                        date = ""
                    }
                    "title" -> if (inItem) title = text(parser)
                    "guid" -> if (inItem) guid = text(parser)
                    "pubDate" -> if (inItem) date = text(parser)
                    "enclosure" -> if (inItem) {
                        enclosure = parser.getAttributeValue(null, "url") ?: ""
                    }
                    "itunes:new-feed-url" -> if (!inItem) movedTo = webAddress(text(parser))
                }
            } else if (event == XmlPullParser.END_TAG && parser.name == "item") {
                inItem = false
                // As the app tells episodes apart: guid, else the audio's
                // address, else the title.
                val key = guid.trim().ifEmpty { enclosure.trim().ifEmpty { title.trim() } }
                if (key.isNotEmpty() && title.isNotBlank()) {
                    episodes.add(Episode(key, title.trim(), published(date)))
                }
            }
            event = parser.next()
        }
        return FeedHead(episodes, movedTo)
    }

    private fun text(parser: XmlPullParser): String = try {
        parser.nextText() ?: ""
    } catch (_: Exception) {
        ""
    }

    private fun webAddress(text: String): String? {
        val address = text.trim()
        return if (address.startsWith("http://") || address.startsWith("https://")) {
            address
        } else {
            null
        }
    }

    private fun published(date: String): Long? {
        val text = date.trim()
        if (text.isEmpty()) return null
        for (pattern in DATE_FORMATS) {
            try {
                return SimpleDateFormat(pattern, Locale.US).parse(text)?.time ?: continue
            } catch (_: Exception) {
            }
        }
        return null
    }

    /**
     * One notification per show: its newest episode's title, or how many
     * there are with their titles listed. Tapped, it opens the Podcasts
     * Inbox. Not without Android 13's permission to notify.
     */
    private fun notify(
        context: Context,
        prefs: SharedPreferences,
        show: Show,
        fresh: List<Episode>,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    prefs.getString(KEY_CHANNEL, null).orEmpty().ifEmpty { "New episodes" },
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val inbox = Intent(
            Intent.ACTION_VIEW,
            Uri.parse(INBOX_LINK),
            context,
            MainActivity::class.java
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        builder.setContentIntent(
            PendingIntent.getActivity(
                context,
                0,
                inbox,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        val newest = fresh.first().title
        val text = if (fresh.size == 1) {
            newest
        } else {
            prefs.getString(KEY_COUNT, null).orEmpty().ifEmpty { "@count new episodes" }
                .replace("@count", "${fresh.size}")
        }
        val style = if (fresh.size == 1) {
            Notification.BigTextStyle().bigText(newest)
        } else {
            Notification.InboxStyle().also { inboxStyle ->
                for (episode in fresh) inboxStyle.addLine(episode.title)
            }
        }
        builder.setSmallIcon(R.drawable.ic_stat_riff)
            .setContentTitle(show.title.ifEmpty { newest })
            .setContentText(text)
            .setStyle(style)
            .setAutoCancel(true)
        artwork(show.art)?.let { builder.setLargeIcon(it) }
        manager.notify(NOTIFICATION_TAG, show.feed.hashCode(), builder.build())
    }

    /** The show's cover for the notification, about [ART_SIZE] across. */
    private fun artwork(address: String): Bitmap? {
        if (webAddress(address) == null) return null
        try {
            val connection = open(address) ?: return null
            val bytes = try {
                connection.inputStream.use { readAtMost(it, ART_MAX_BYTES) }
            } finally {
                connection.disconnect()
            }
            if (bytes == null) return null
            val bounds = BitmapFactory.Options()
            bounds.inJustDecodeBounds = true
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= ART_SIZE &&
                bounds.outHeight / (sample * 2) >= ART_SIZE
            ) {
                sample *= 2
            }
            val options = BitmapFactory.Options()
            options.inSampleSize = sample
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } catch (_: Exception) {
            return null
        }
    }

    /** All of [stream], or null when it's more than [limit] bytes. */
    private fun readAtMost(stream: InputStream, limit: Int): ByteArray? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        while (true) {
            val n = stream.read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
            if (out.size() > limit) return null
        }
        return out.toByteArray()
    }
}

/**
 * The look at the followed shows' feeds (scheduled by [EpisodeAlerts]),
 * off the main thread, when Android runs it: every few hours on a
 * connection, and once more when a show was followed.
 */
class NewEpisodesJob : JobService() {
    @Volatile
    private var stopped = false

    override fun onStartJob(params: JobParameters): Boolean {
        stopped = false
        val context = applicationContext
        Thread {
            try {
                EpisodeAlerts.check(context) { stopped }
            } catch (_: Exception) {
            }
            jobFinished(params, false)
        }.start()
        return true
    }

    // The next look comes with the next interval.
    override fun onStopJob(params: JobParameters): Boolean {
        stopped = true
        return false
    }
}
