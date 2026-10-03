import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'spotify_api_service.dart';
import 'spotify_auth_service.dart';
import 'spotify_import_service.dart';
import 'spotify_match.dart';
import 'spotify_match_store.dart';

enum LikeOp { save, remove }

/// [pending] with [op] for [videoId] added. A like and an unlike of the
/// same song before they're sent cancel out.
Map<String, LikeOp> queueLikeOp(
    Map<String, LikeOp> pending, String videoId, LikeOp op) {
  final out = Map<String, LikeOp>.from(pending);
  final before = out[videoId];
  if (before != null && before != op) {
    out.remove(videoId);
  } else {
    out[videoId] = op;
  }
  return out;
}

/// What to send to Spotify for the queued changes.
class LikeFlushPlan {
  const LikeFlushPlan(
      {this.save = const [], this.remove = const [], this.done = const []});

  /// Spotify track ids to add to Liked Songs.
  final List<String> save;

  /// Spotify track ids to take out of Liked Songs.
  final List<String> remove;

  /// Queued songs settled without a call (already liked, not Riff's to
  /// remove, or no Spotify track for them).
  final List<String> done;
}

/// Turn queued changes into calls. Riff only removes from Spotify what it
/// added there itself: a song liked on Spotify stays liked there when it's
/// unliked in Riff. Songs already liked on Spotify aren't saved again.
/// [spotifyIdFor] gives the Spotify track for a song, '' when there's none,
/// and no entry when it isn't known yet (it stays queued).
LikeFlushPlan planLikeFlush({
  required Map<String, LikeOp> pending,
  required Map<String, String> spotifyIdFor,
  required Set<String> addedByRiff,
  required Set<String> likedOnSpotify,
}) {
  final save = <String>[], remove = <String>[], done = <String>[];
  pending.forEach((videoId, op) {
    final id = spotifyIdFor[videoId];
    if (id == null) return; // unresolved: try again later
    if (id.isEmpty) {
      done.add(videoId);
      return;
    }
    if (op == LikeOp.save) {
      if (likedOnSpotify.contains(id)) {
        done.add(videoId);
      } else if (!save.contains(id)) {
        save.add(id);
      }
    } else {
      if (addedByRiff.contains(id)) {
        if (!remove.contains(id)) remove.add(id);
      } else {
        done.add(videoId);
      }
    }
  });
  return LikeFlushPlan(save: save, remove: remove, done: done);
}

/// Score below which a Spotify search result isn't taken as the same song
/// (stricter than playback matching: this writes to the user's account).
const double kMinLikeMatch = 0.6;

/// The Spotify track among [candidates] that is [song], or null.
SpotifyTrackRef? pickSpotifyTrackFor(
    MediaItem song, List<SpotifyTrackRef> candidates) {
  final best = bestMatch<SpotifyTrackRef>(
    candidates,
    score: (c) => matchScore(
      spotifyTitle: c.title,
      spotifyArtists: c.artists,
      spotifyDurationMs: c.durationMs,
      candidateTitle: song.title,
      candidateArtist: song.artist,
      candidateDuration: song.duration,
    ),
    minScore: kMinLikeMatch,
  );
  return best?.item;
}

/// Mirrors likes made in Riff to Spotify's Liked Songs (opt-in, off by
/// default). Riff's Favorites and Spotify's Liked Songs stay separate
/// lists; this only adds and removes what Riff itself changed, a few
/// seconds after the change, in batches.
class SpotifyLikeSync {
  SpotifyLikeSync._();

  static const queueBox = 'SpotifyLikeQueue';
  static const reverseBox = 'SpotifyReverseMatches';
  static const addedBox = 'SpotifyLikedByRiff';

  /// Wait this long after a change before sending, to batch changes.
  static const debounce = Duration(seconds: 15);

  /// Songs with no Spotify track are looked up again after this long.
  static const notFoundRetry = Duration(days: 30);

  static final pending = 0.obs;
  static final lastError = ''.obs;
  static Timer? _timer;
  static Future<void>? _flushing;
  static var _suppress = false;

  static bool get enabled => SpotifyAuthService.likeSyncOn;

  static Future<Box> _open(String name) async =>
      Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);

  static Future<void> setEnabled(bool on) async {
    await Hive.box('AppPrefs').put(SpotifyAuthService.likeSyncKey, on);
    if (!on) {
      _timer?.cancel();
      await (await _open(queueBox)).clear();
      pending.value = 0;
    }
  }

  /// Forget what belongs to the signed-out account (queued changes, which
  /// songs Riff added to its Liked Songs, looked-up tracks).
  static Future<void> forgetAccount() async {
    _timer?.cancel();
    for (final b in [queueBox, addedBox, reverseBox]) {
      await (await _open(b)).clear();
    }
    pending.value = 0;
    lastError.value = '';
  }

  /// Whether the current sign-in may change Liked Songs.
  static bool get hasWriteAccess =>
      SpotifyAuthService.isConnected &&
      !SpotifyAuthService.lacksScope(SpotifyAuthService.libraryWriteScope);

  /// Run [action] without queueing the Favorites changes it makes (they
  /// come from Spotify).
  static Future<T> quietly<T>(Future<T> Function() action) async {
    _suppress = true;
    try {
      return await action();
    } finally {
      _suppress = false;
    }
  }

  /// A song was added to or removed from Riff's Favorites.
  static Future<void> onFavorite(MediaItem song, {required bool add}) async {
    if (_suppress || !enabled || !SpotifyAuthService.isConnected) return;
    try {
      final box = await _open(queueBox);
      final current = <String, LikeOp>{
        for (final k in box.keys)
          if (_opOf(box.get(k)) case final op?) '$k': op
      };
      final next =
          queueLikeOp(current, song.id, add ? LikeOp.save : LikeOp.remove);
      if (next.containsKey(song.id)) {
        await box.put(song.id, {
          'op': next[song.id]!.name,
          'title': song.title,
          'artist': song.artist,
          'durationMs': song.duration?.inMilliseconds,
        });
      } else {
        await box.delete(song.id);
      }
      pending.value = box.length;
      flushSoon();
    } catch (e) {
      printERROR('Spotify like queue failed: $e');
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

  /// Send what's queued. One at a time.
  static Future<void> flush({SpotifyApiService? api}) =>
      _flushing ??= _flush(api).whenComplete(() => _flushing = null);

  static Future<void> _flush(SpotifyApiService? apiOverride) async {
    if (!enabled || !hasWriteAccess) return;
    final queue = await _open(queueBox);
    if (queue.isEmpty) {
      pending.value = 0;
      return;
    }
    final api = apiOverride ?? SpotifyApiService(auth: SpotifyAuthService());
    final reverse = await _open(reverseBox);
    final added = await _open(addedBox);
    try {
      final ops = <String, LikeOp>{
        for (final k in queue.keys)
          if (_opOf(queue.get(k)) case final op?) '$k': op
      };
      final ids = <String, String>{};
      for (final videoId in ops.keys) {
        final id =
            await _spotifyIdFor(videoId, queue.get(videoId), api, reverse);
        if (id != null) ids[videoId] = id;
      }
      final liked = {
        for (final t in await api.fetchLikedSongs()) t.id,
      };
      final plan = planLikeFlush(
        pending: ops,
        spotifyIdFor: ids,
        addedByRiff: {for (final k in added.keys) '$k'},
        likedOnSpotify: liked,
      );
      if (plan.save.isNotEmpty) {
        await api.saveTracks(plan.save);
        final now = DateTime.now().millisecondsSinceEpoch;
        await added.putAll({for (final id in plan.save) id: now});
      }
      if (plan.remove.isNotEmpty) {
        await api.removeTracks(plan.remove);
        await added.deleteAll(plan.remove);
      }
      final sent = {...plan.save, ...plan.remove};
      await queue.deleteAll([
        ...plan.done,
        for (final e in ids.entries)
          if (sent.contains(e.value)) e.key
      ]);
      if (sent.isNotEmpty) await SpotifyApiService.clearCache();
      lastError.value = '';
    } on SpotifyApiException catch (e) {
      lastError.value = e.kind.name;
    } catch (e) {
      printERROR('Spotify like sync failed: $e');
      lastError.value = SpotifyErrorKind.server.name;
    } finally {
      pending.value = queue.length;
    }
  }

  /// The Spotify track id for a Riff song: from a Spotify match, a lookup
  /// done before, or a Spotify search. '' when Spotify has no such song.
  static Future<String?> _spotifyIdFor(
      String videoId, Object? meta, SpotifyApiService api, Box reverse) async {
    final cached = reverse.get(videoId);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached is Map && cached['id'] is String) {
      final id = cached['id'] as String;
      final at = cached['at'] is int ? cached['at'] as int : 0;
      if (id.isNotEmpty || now - at < notFoundRetry.inMilliseconds) return id;
    }
    final fromMatches = await _fromMatchStore(videoId);
    if (fromMatches != null) {
      await reverse.put(videoId, {'id': fromMatches, 'at': now});
      return fromMatches;
    }
    if (meta is! Map) return null;
    final dur = meta['durationMs'];
    final song = MediaItem(
      id: videoId,
      title: '${meta['title'] ?? ''}',
      artist: meta['artist']?.toString(),
      duration: dur is int && dur > 0 ? Duration(milliseconds: dur) : null,
    );
    final query = '${song.title} ${song.artist ?? ''}'.trim();
    if (query.isEmpty) return '';
    final found = pickSpotifyTrackFor(song, await api.searchTracks(query));
    final id = found?.id ?? '';
    await reverse.put(videoId, {'id': id, 'at': now});
    return id;
  }

  static Future<String?> _fromMatchStore(String videoId) async {
    final box = await SpotifyMatchStore.open();
    if (box == null) return null;
    for (final k in box.keys) {
      final e = SpotifyMatchEntry.fromJson(box.get(k));
      if (e != null && e.videoId == videoId) return '$k';
    }
    return null;
  }

  /// Add every Spotify Liked Song that can be found on YouTube Music to
  /// Riff's Favorites. Returns (added, total).
  static Future<(int, int)> importLikesToFavorites(
      Future<bool> Function(List<MediaItem>) addToFavorites,
      {void Function(int done, int total)? onProgress}) async {
    final api = SpotifyApiService(auth: SpotifyAuthService());
    final tracks = await api.fetchLikedSongs(force: true);
    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService());
    }
    final items = (await Get.find<SpotifyImportService>()
            .resolveTracksDetailed(tracks, onProgress: onProgress))
        .whereType<MediaItem>()
        .toList();
    if (items.isNotEmpty) await quietly(() => addToFavorites(items));
    return (items.length, tracks.length);
  }
}
