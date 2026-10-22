import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';
import '../models/media_item_extras.dart';
import '../utils/helper.dart';
import '../utils/hive_boxes.dart';
import 'music_service.dart';
import 'spotify_like_sync.dart' show LikeOp;
import 'yt_auth_service.dart';
import 'yt_history_sync.dart';

/// Keeps your likes in step with YouTube Music once your YouTube account
/// is connected (opt-in), as Metrolist syncs them: your YouTube Music likes
/// come into Riff's Favorites (when it's turned on, then once a day), and a
/// song liked or unliked in Riff is liked or unliked in YouTube Music too,
/// so Liked music there matches and steers the feed Riff shows you.
/// Changes go a few seconds after they're made and wait (across restarts)
/// while YouTube can't be reached.
class YtLikeSync {
  YtLikeSync._();

  static const queueBox = 'YtLikeQueue';

  /// AppPrefs: whether likes are kept in step.
  static const enabledKey = 'ytLikeSync';

  /// AppPrefs: when your YouTube Music likes last came in.
  static const importedAtKey = 'ytLikesImportedAt';

  /// Wait this long after a change before sending, to batch changes.
  static const debounce = Duration(seconds: 10);

  /// Changes not sent yet.
  static final pending = 0.obs;

  /// Bumps when the switch changes.
  static final rev = 0.obs;

  static Timer? _timer;
  static Future<void>? _flushing;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static bool get enabled => _prefs?.get(enabledKey) == true;

  /// Rates [videoId] on the connected account ('like/like' or
  /// 'like/removelike'); whether YouTube took it. Tests replace it.
  @visibleForTesting
  static Future<bool> Function(String endpoint, String videoId) send =
      (endpoint, videoId) =>
          Get.find<MusicServices>().rateSong(endpoint, videoId);

  /// Whether a YouTube account is connected; tests replace it.
  @visibleForTesting
  static bool Function() connected = () => YtAuthService.isConnected;

  /// Your YouTube Music likes (its Liked music, the latest first), the
  /// first [limit] of them or all; tests replace it.
  @visibleForTesting
  static Future<List<MediaItem>> Function({int? limit}) fetchLikes =
      ({int? limit}) async {
    final page = await Get.find<MusicServices>()
        .getPlaylistOrAlbumSongs(playlistId: 'LM', limit: limit);
    return [
      for (final t in page['tracks'] as List? ?? const [])
        if (t is MediaItem) t,
    ];
  };

  /// Your YouTube Music likes (all, or the latest [limit]) into Riff's
  /// Favorites: the songs not in them yet (no episodes). Written straight
  /// to Favorites, so they aren't sent back to YouTube, to Spotify, or
  /// downloaded. How many came; null when the likes couldn't be read.
  static Future<int?> importLikes({DateTime? now, int? limit}) async {
    if (!connected()) return null;
    final List<MediaItem> likes;
    try {
      likes = await fetchLikes(limit: limit);
    } catch (e) {
      printERROR('YouTube Music likes not read: $e');
      return null;
    }
    final fav = await HiveBoxes.fav();
    // Unliked in Riff, its unlike still on its way: it stays out.
    final queue = await _open(queueBox);
    bool unliking(String id) => _opOf(queue.get(id)) == LikeOp.remove;
    final fresh = <String, dynamic>{
      for (final song in likes)
        if (_videoId.hasMatch(song.id) &&
            !song.isPodcastEpisode &&
            !fav.containsKey(song.id) &&
            !unliking(song.id))
          song.id: MediaItemBuilder.toJson(song),
    };
    if (fresh.isNotEmpty) await fav.putAll(fresh);
    await _prefs?.put(
        importedAtKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
    return fresh.length;
  }

  /// How many of the latest likes the daily look reads (new ones are first).
  static const dailyLimit = 200;

  /// While in step, likes made in YouTube Music come in once a day (all of
  /// them the first time, when they couldn't come in as it was turned on).
  static Future<void> importLikesDaily({DateTime? now}) async {
    if (!enabled || !connected()) return;
    final n = now ?? DateTime.now();
    final last = _prefs?.get(importedAtKey);
    if (last is int &&
        n.millisecondsSinceEpoch - last <
            const Duration(days: 1).inMilliseconds) {
      return;
    }
    await importLikes(now: n, limit: last is int ? dailyLimit : null);
  }

  static Future<Box> _open(String name) async =>
      Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);

  static Future<void> setEnabled(bool on) async {
    await _prefs?.put(enabledKey, on);
    rev.value++;
    if (!on) {
      _timer?.cancel();
      await (await _open(queueBox)).clear();
      pending.value = 0;
    }
  }

  /// Forget what belongs to the disconnected account: the changes not sent
  /// and when its likes last came in.
  static Future<void> forgetAccount() async {
    _timer?.cancel();
    await (await _open(queueBox)).clear();
    await _prefs?.delete(importedAtKey);
    pending.value = 0;
  }

  /// A song was added to or taken out of Riff's Favorites.
  static Future<void> onFavorite(MediaItem song, {required bool add}) async {
    // A YouTube song only: a phone song's id can look like a video's.
    if (!enabled || !connected() || !YtHistorySync.counts(song)) return;
    try {
      final box = await _open(queueBox);
      // The latest change wins and goes even when it undoes one not sent
      // yet: the song may be liked in YouTube Music already, and liking or
      // unliking it twice does no harm.
      await box.put(song.id, {'op': (add ? LikeOp.save : LikeOp.remove).name});
      pending.value = box.length;
      flushSoon();
    } catch (e) {
      printERROR('YouTube like queue failed: $e');
    }
  }

  static LikeOp? _opOf(Object? v) => v is Map
      ? LikeOp.values.firstWhereOrNull((o) => o.name == v['op'])
      : null;

  static void flushSoon({Duration delay = debounce}) {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  /// Send what's waiting; one flush at a time. What YouTube doesn't take
  /// (offline, signed out, refused) is kept for the next time.
  static Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  static Future<void> _flush() async {
    if (!enabled || !connected()) return;
    final queue = await _open(queueBox);
    try {
      for (final key in queue.keys.toList()) {
        final sent = queue.get(key);
        final op = _opOf(sent);
        // One YouTube won't take stays for next time without holding up
        // the changes after it.
        if (op != null &&
            !await send(
                op == LikeOp.save ? 'like/like' : 'like/removelike', '$key')) {
          continue;
        }
        // Changed while it went (liked, then unliked at once): the newer
        // change still goes.
        if (op != null && _opOf(queue.get(key)) != op) continue;
        await queue.delete(key);
      }
    } catch (e) {
      printERROR('YouTube like sync failed: $e');
    } finally {
      pending.value = queue.length;
    }
  }
}
