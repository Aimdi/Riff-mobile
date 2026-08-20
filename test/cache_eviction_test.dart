import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/cache_eviction.dart';

CachedSongEntry _e(String id, {int size = 100, int access = 0}) =>
    CachedSongEntry(id: id, sizeBytes: size, lastAccessMs: access);

void main() {
  group('planSongCacheEviction', () {
    test('never evicts protected ids even when over budget', () {
      final decision = planSongCacheEviction(
        entries: [
          _e('playing', size: 800, access: 1),
          _e('queued', size: 800, access: 1),
        ],
        protectedIds: {'playing', 'queued'},
        nowMs: 1000,
        maxBytes: 100,
      );
      expect(decision.idsToDelete, isEmpty);
      expect(decision.keptBytes, 1600);
    });

    test('evicts least-recently-played first to fit max size', () {
      final decision = planSongCacheEviction(
        entries: [
          _e('old', size: 60, access: 10),
          _e('mid', size: 60, access: 20),
          _e('fresh', size: 60, access: 30),
        ],
        protectedIds: const {},
        nowMs: 100,
        maxBytes: 100,
      );
      expect(decision.idsToDelete, ['old', 'mid']);
      expect(decision.bytesToFree, 120);
      expect(decision.keptBytes, 60);
    });

    test('age eviction removes stale files before size pass', () {
      const day = 24 * 60 * 60 * 1000;
      const now = 40 * day;
      final decision = planSongCacheEviction(
        entries: [
          _e('stale', size: 10, access: now - 35 * day),
          _e('fresh', size: 10, access: now - 2 * day),
        ],
        protectedIds: const {},
        nowMs: now,
        maxBytes: 1000,
        maxAgeMs: 30 * day,
      );
      expect(decision.idsToDelete, ['stale']);
    });

    test('protected stale files survive age eviction', () {
      const day = 24 * 60 * 60 * 1000;
      const now = 40 * day;
      final decision = planSongCacheEviction(
        entries: [
          _e('playing', size: 10, access: now - 35 * day),
        ],
        protectedIds: {'playing'},
        nowMs: now,
        maxBytes: 1,
        maxAgeMs: 30 * day,
      );
      expect(decision.idsToDelete, isEmpty);
    });

    test('unlimited size with no age keeps everything', () {
      final decision = planSongCacheEviction(
        entries: [_e('a', size: 9999, access: 1)],
        protectedIds: const {},
        nowMs: 100,
        maxBytes: SongCacheLimits.unlimitedBytes,
      );
      expect(decision.idsToDelete, isEmpty);
    });

    test('empty id is ignored', () {
      final decision = planSongCacheEviction(
        entries: [_e('', size: 500, access: 1)],
        protectedIds: const {},
        nowMs: 100,
        maxBytes: 1,
      );
      expect(decision.idsToDelete, isEmpty);
    });
  });

  group('SongCacheLimits.coerce', () {
    test('keeps known options and falls back to 1 GB', () {
      expect(SongCacheLimits.coerce(0), 0);
      expect(SongCacheLimits.coerce(SongCacheLimits.defaultMaxBytes),
          SongCacheLimits.defaultMaxBytes);
      expect(SongCacheLimits.coerce(null), SongCacheLimits.defaultMaxBytes);
      expect(SongCacheLimits.coerce(99), SongCacheLimits.defaultMaxBytes);
    });
  });

  group('formatCacheBytes', () {
    test('formats KB MB GB', () {
      expect(formatCacheBytes(512), '512 B');
      expect(formatCacheBytes(2048), '2 KB');
      expect(formatCacheBytes(3 * 1024 * 1024), '3.0 MB');
      expect(formatCacheBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });
}
