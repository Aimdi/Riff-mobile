/// One auto-cached song file plus the metadata used to rank it for LRU.
class CachedSongEntry {
  const CachedSongEntry({
    required this.id,
    required this.sizeBytes,
    required this.lastAccessMs,
  });

  final String id;
  final int sizeBytes;

  /// Last play / last file access, milliseconds since epoch.
  final int lastAccessMs;
}

class CacheEvictionDecision {
  const CacheEvictionDecision({
    required this.idsToDelete,
    required this.bytesToFree,
    required this.keptBytes,
  });

  final List<String> idsToDelete;
  final int bytesToFree;
  final int keptBytes;
}

/// Defaults for auto-cached songs (`SongsCache` / `cachedSongs/*.mp3`).
/// User downloads (`SongDownloads`) are never passed into this policy.
class SongCacheLimits {
  static const defaultMaxBytes = 1024 * 1024 * 1024; // 1 GB
  static const defaultMaxAge = Duration(days: 30);
  static const unlimitedBytes = 0;

  static const options = <int>[
    500 * 1024 * 1024,
    defaultMaxBytes,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
    unlimitedBytes,
  ];

  static int coerce(dynamic raw) {
    if (raw is int && options.contains(raw)) return raw;
    if (raw is num) {
      final n = raw.toInt();
      if (options.contains(n)) return n;
    }
    return defaultMaxBytes;
  }
}

/// LRU / least-recently-played eviction for song files.
///
/// [protectedIds] (now playing + queue) are never returned.
/// Age eviction runs first, then size eviction on what remains.
CacheEvictionDecision planSongCacheEviction({
  required List<CachedSongEntry> entries,
  required Set<String> protectedIds,
  required int nowMs,
  int maxBytes = SongCacheLimits.defaultMaxBytes,
  int maxAgeMs = 0,
}) {
  final candidates = entries
      .where((e) => e.id.isNotEmpty && !protectedIds.contains(e.id))
      .toList();

  final toDelete = <String>{};
  var freed = 0;

  if (maxAgeMs > 0) {
    for (final e in candidates) {
      if (nowMs - e.lastAccessMs >= maxAgeMs) {
        toDelete.add(e.id);
        freed += e.sizeBytes;
      }
    }
  }

  var remainingBytes = entries.fold<int>(0, (sum, e) => sum + e.sizeBytes) -
      freed;
  if (maxBytes > 0 && remainingBytes > maxBytes) {
    final leftover = candidates.where((e) => !toDelete.contains(e.id)).toList()
      ..sort((a, b) {
        final byAccess = a.lastAccessMs.compareTo(b.lastAccessMs);
        if (byAccess != 0) return byAccess;
        return b.sizeBytes.compareTo(a.sizeBytes);
      });
    for (final e in leftover) {
      if (remainingBytes <= maxBytes) break;
      toDelete.add(e.id);
      freed += e.sizeBytes;
      remainingBytes -= e.sizeBytes;
    }
  }

  return CacheEvictionDecision(
    idsToDelete: toDelete.toList(growable: false),
    bytesToFree: freed,
    keptBytes: entries.fold<int>(0, (sum, e) => sum + e.sizeBytes) - freed,
  );
}

String formatCacheBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String songCacheLimitLabel(int maxBytes) {
  if (maxBytes <= 0) return 'songsCacheUnlimited';
  if (maxBytes <= 500 * 1024 * 1024) return 'songsCache500mb';
  if (maxBytes <= 1024 * 1024 * 1024) return 'songsCache1gb';
  if (maxBytes <= 2 * 1024 * 1024 * 1024) return 'songsCache2gb';
  return 'songsCache5gb';
}
