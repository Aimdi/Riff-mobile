package com.anandnet.harmonymusic

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * "riff/device_music": the music files on the phone, from MediaStore, as
 * Spotify's Local files and YouTube Music's Device files list them, for
 * the Songs library's "On this phone" (lib/services/device_music.dart).
 * Each album's cover is written once, to the folder Dart names
 * (album_<id>.jpg), for the app's covers and the media notification.
 * Needs no activity; the listing runs off the main thread.
 */
object DeviceMusic : MethodChannel.MethodCallHandler {
    /** Set by MainActivity. */
    var appContext: Context? = null

    private val main = Handler(Looper.getMainLooper())

    /** Shorter files are ringtones, notification sounds and voice notes. */
    private const val MIN_DURATION_MS = 30_000L
    private const val ART_SIZE = 512

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.success(null)
            return
        }
        when (call.method) {
            "songs" -> {
                val artDir = call.argument<String>("artDir")
                Thread {
                    val songs = try {
                        songs(context, artDir)
                    } catch (_: Exception) {
                        // No permission to read them (SecurityException), or
                        // MediaStore can't be asked: Dart says so.
                        null
                    }
                    main.post { result.success(songs) }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    /** Every song, by title: {id, uri, title, artist, album, albumId, durationMs, addedSec, art}. */
    private fun songs(context: Context, artDir: String?): List<Map<String, Any?>> {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND " +
            "${MediaStore.Audio.Media.DURATION} >= ?"
        val songs = ArrayList<HashMap<String, Any?>>()
        // One song of each album, to read the album's cover from.
        val albums = LinkedHashMap<Long, Uri>()
        context.contentResolver.query(
            collection,
            projection,
            selection,
            arrayOf(MIN_DURATION_MS.toString()),
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val addedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idColumn)
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id
                )
                val albumId = cursor.getLong(albumIdColumn)
                if (!albums.containsKey(albumId)) albums[albumId] = uri
                songs.add(
                    hashMapOf(
                        "id" to id.toString(),
                        "uri" to uri.toString(),
                        "title" to cursor.getString(titleColumn),
                        "artist" to cursor.getString(artistColumn),
                        "album" to cursor.getString(albumColumn),
                        "albumId" to albumId.toString(),
                        "durationMs" to cursor.getLong(durationColumn),
                        "addedSec" to cursor.getLong(addedColumn),
                    )
                )
            }
        }
        if (artDir != null) {
            val covers = covers(context, albums, File(artDir))
            for (song in songs) {
                val albumId = (song["albumId"] as? String)?.toLongOrNull() ?: continue
                covers[albumId]?.let { song["art"] = it }
            }
        }
        return songs
    }

    /**
     * Each album's cover as [dir]/album_<id>.jpg, written the first time
     * (an album without one is noted, album_<id>.none, not looked at
     * again); the paths of those there are.
     */
    private fun covers(context: Context, albums: Map<Long, Uri>, dir: File): Map<Long, String> {
        dir.mkdirs()
        val paths = HashMap<Long, String>()
        for ((albumId, songUri) in albums) {
            val file = File(dir, "album_$albumId.jpg")
            val none = File(dir, "album_$albumId.none")
            if (!file.exists() && !none.exists()) {
                val cover = try {
                    cover(context, albumId, songUri)
                } catch (_: Exception) {
                    null
                }
                if (cover == null) {
                    try {
                        none.createNewFile()
                    } catch (_: Exception) {
                    }
                } else {
                    try {
                        FileOutputStream(file).use {
                            cover.compress(Bitmap.CompressFormat.JPEG, 85, it)
                        }
                    } catch (_: Exception) {
                        file.delete()
                    }
                    cover.recycle()
                }
            }
            if (file.exists()) paths[albumId] = file.absolutePath
        }
        return paths
    }

    private fun cover(context: Context, albumId: Long, songUri: Uri): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.contentResolver.loadThumbnail(songUri, Size(ART_SIZE, ART_SIZE), null)
        }
        val art = ContentUris.withAppendedId(
            Uri.parse("content://media/external/audio/albumart"),
            albumId
        )
        // Its size first (decoding only the bounds gives no bitmap), so a
        // big cover is read scaled down.
        val bounds = BitmapFactory.Options()
        bounds.inJustDecodeBounds = true
        val stream = context.contentResolver.openInputStream(art) ?: return null
        stream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= ART_SIZE &&
            bounds.outHeight / (sample * 2) >= ART_SIZE
        ) {
            sample *= 2
        }
        val options = BitmapFactory.Options()
        options.inSampleSize = sample
        return context.contentResolver.openInputStream(art)?.use {
            BitmapFactory.decodeStream(it, null, options)
        }
    }
}
