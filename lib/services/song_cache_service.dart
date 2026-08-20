import 'dart:io';

import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item_extras.dart';
import '../ui/player/player_controller.dart';
import '../utils/helper.dart';
import '../utils/hive_boxes.dart';
import 'cache_eviction.dart';

/// Auto-cached songs (`cachedSongs/*.mp3` + `SongsCache` Hive).
/// Never touches user downloads in `SongDownloads`.
class SongCacheService {
  SongCacheService();

  static DateTime? _lastEvictAt;
  static const _evictCooldown = Duration(minutes: 10);

  Future<Directory> cachedSongsDir() async {
    final cacheDir = (await getTemporaryDirectory()).path;
    return Directory('$cacheDir/cachedSongs');
  }

  Future<Directory> imageCacheDir() async {
    final cacheDir = (await getApplicationCacheDirectory()).path;
    return Directory('$cacheDir/libCachedImageData');
  }

  Future<int> _directorySize(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<int> songsCacheBytes() async => _directorySize(await cachedSongsDir());

  Future<int> imageCacheBytes() async => _directorySize(await imageCacheDir());

  Future<int> downloadsBytes() async {
    final box = HiveBoxes.songDownloadsSync();
    if (box == null) return 0;
    var total = 0;
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final path = raw['url']?.toString() ?? '';
      if (path.isEmpty) continue;
      final file = File(path.startsWith('file://') ? path.substring(7) : path);
      try {
        if (await file.exists()) total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  Set<String> protectedPlaybackIds() {
    if (!Get.isRegistered<PlayerController>()) return {};
    final player = Get.find<PlayerController>();
    final ids = mediaItemIds(player.currentQueue);
    final current = player.currentSong.value?.id;
    if (current != null && current.isNotEmpty) ids.add(current);
    return ids;
  }

  int _lastAccessMs({
    required String id,
    required int fileMtimeMs,
    required Map? hiveRecord,
  }) {
    var latest = fileMtimeMs;
    final hiveDate = hiveRecord?['date'];
    if (hiveDate is int && hiveDate > latest) latest = hiveDate;
    final stats = HiveBoxes.songStatsSync()?.get(id);
    if (stats is Map) {
      final lastPlayed = stats['lastPlayed'];
      if (lastPlayed is int && lastPlayed > latest) latest = lastPlayed;
    }
    return latest;
  }

  Future<List<CachedSongEntry>> _scanEntries() async {
    final dir = await cachedSongsDir();
    if (!await dir.exists()) return const [];
    final box = HiveBoxes.songsCacheSync();
    final entries = <CachedSongEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!name.endsWith('.mp3')) continue;
      if (name.endsWith('.mp3.part') || name.contains('.mime')) continue;
      final id = name.substring(0, name.length - 4);
      if (id.isEmpty) continue;
      try {
        final stat = await entity.stat();
        final hive = box?.get(id);
        entries.add(CachedSongEntry(
          id: id,
          sizeBytes: stat.size,
          lastAccessMs: _lastAccessMs(
            id: id,
            fileMtimeMs: stat.modified.millisecondsSinceEpoch,
            hiveRecord: hive is Map ? hive : null,
          ),
        ));
      } catch (_) {}
    }
    return entries;
  }

  Future<void> _deleteCachedSong(String id) async {
    final dir = await cachedSongsDir();
    final file = File('${dir.path}/$id.mp3');
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      printERROR('song cache delete file failed ($id): $e');
    }
    try {
      HiveBoxes.songsCacheSync()?.delete(id);
    } catch (e) {
      printERROR('song cache delete hive failed ($id): $e');
    }
  }

  /// Cheap background pass. No-ops during cooldown so resume + init stay cheap.
  Future<CacheEvictionDecision?> evictIfNeeded({
    bool force = false,
    Set<String>? protectedIds,
    int? maxBytes,
    Duration maxAge = SongCacheLimits.defaultMaxAge,
  }) async {
    final now = DateTime.now();
    if (!force &&
        _lastEvictAt != null &&
        now.difference(_lastEvictAt!) < _evictCooldown) {
      return null;
    }
    _lastEvictAt = now;

    final prefs = HiveBoxes.maybe(HiveBoxes.appPrefs);
    final limit = maxBytes ??
        (prefs?.get('songsCacheMaxBytes') as int?) ??
        SongCacheLimits.defaultMaxBytes;
    final entries = await _scanEntries();
    if (entries.isEmpty) {
      return const CacheEvictionDecision(
        idsToDelete: [],
        bytesToFree: 0,
        keptBytes: 0,
      );
    }
    final decision = planSongCacheEviction(
      entries: entries,
      protectedIds: protectedIds ?? protectedPlaybackIds(),
      nowMs: now.millisecondsSinceEpoch,
      maxBytes: limit,
      maxAgeMs: maxAge.inMilliseconds,
    );
    for (final id in decision.idsToDelete) {
      await _deleteCachedSong(id);
    }
    if (decision.idsToDelete.isNotEmpty) {
      printINFO(
          'song cache evicted ${decision.idsToDelete.length} files '
          '(${formatCacheBytes(decision.bytesToFree)})');
    }
    return decision;
  }

  /// Settings "Clear cached songs". Playing / queued files stay.
  Future<List<String>> clearCachedSongs({Set<String>? protectedIds}) async {
    final keep = protectedIds ?? protectedPlaybackIds();
    final entries = await _scanEntries();
    final removed = <String>[];
    for (final e in entries) {
      if (keep.contains(e.id)) continue;
      await _deleteCachedSong(e.id);
      removed.add(e.id);
    }
    return removed;
  }
}
