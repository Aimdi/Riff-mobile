import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';

MediaItem absTrack(String bookId, int index, {Map<String, dynamic>? extras}) =>
    MediaItem(
      id: 'abs_${bookId}_$index',
      title: 'Chapter $index',
      extras: extras ?? {'absItemId': bookId, 'absTrackIndex': index},
    );

void main() {
  group('AudiobookProgressService.isAudiobookItem', () {
    test('recognises Audiobookshelf tracks', () {
      expect(
          AudiobookProgressService.isAudiobookItem(absTrack('bk1', 3)), isTrue);
    });

    // Regression: before this existed, audiobooks fell through every
    // long-form branch, so no position was ever written and every chapter
    // restarted from zero.
    test('does not claim podcasts, cloud songs, or YouTube tracks', () {
      for (final id in ['podcast_ep1', 'cloud_42', 'dQw4w9WgXcQ']) {
        expect(
          AudiobookProgressService.isAudiobookItem(
              MediaItem(id: id, title: 't')),
          isFalse,
          reason: '$id must not be treated as an audiobook',
        );
      }
    });
  });

  group('bookIdOf', () {
    test('prefers the explicit extras value', () {
      expect(AudiobookProgressService.bookIdOf(absTrack('bk1', 2)), 'bk1');
    });

    test('falls back to parsing the id when extras are absent', () {
      const t = MediaItem(id: 'abs_bk9_12', title: 'c', extras: {});
      expect(AudiobookProgressService.bookIdOf(t), 'bk9');
    });

    // Book ids may themselves contain underscores, so only the final
    // separator delimits the track index.
    test('handles book ids containing underscores', () {
      const t = MediaItem(id: 'abs_lib_col_77_4', title: 'c', extras: {});
      expect(AudiobookProgressService.bookIdOf(t), 'lib_col_77');
    });

    test('returns null for a non-audiobook id', () {
      expect(
        AudiobookProgressService.bookIdOf(
            const MediaItem(id: 'podcast_1', title: 'p')),
        isNull,
      );
    });
  });

  group('isFinished', () {
    test('a track near its end is finished so it does not resume at the end',
        () {
      const total = 600000; // 10 min
      expect(AudiobookProgressService.isFinished(total - 5000, total), isTrue);
      expect(AudiobookProgressService.isFinished(total, total), isTrue);
    });

    test('mid-track is not finished', () {
      expect(AudiobookProgressService.isFinished(300000, 600000), isFalse);
    });

    // A long chapter must not be declared finished by the 20s rule alone:
    // 98% of a 2-hour chapter is still ~2.5 minutes of audio.
    test('uses the proportional rule for long chapters', () {
      const twoHours = 7200000;
      // 98% of two hours is 7,056,000ms, and the 20s rule alone would only
      // trigger at 7,180,000ms — so the proportional rule is what fires here.
      expect(AudiobookProgressService.isFinished(7000000, twoHours), isFalse);
      expect(AudiobookProgressService.isFinished(7100000, twoHours), isTrue);
    });

    test('unknown duration is never finished', () {
      expect(AudiobookProgressService.isFinished(1000, 0), isFalse);
    });
  });

  group('isTooEarly', () {
    test('ignores the first 15s so a stray tap cannot clobber a real position',
        () {
      expect(AudiobookProgressService.isTooEarly(0), isTrue);
      expect(AudiobookProgressService.isTooEarly(14999), isTrue);
      expect(AudiobookProgressService.isTooEarly(15000), isFalse);
    });
  });

  group('save without an open box', () {
    test('is a no-op rather than throwing', () {
      expect(
        () => AudiobookProgressService.save(absTrack('bk1', 1),
            const Duration(minutes: 5), const Duration(minutes: 40),
            nowMs: 1),
        returnsNormally,
      );
    });
  });

  group('server sync conversion', () {
    MediaItem trackWith(Map<String, dynamic> extras) =>
        MediaItem(id: 'abs_bk_2', title: 'Ch 3', extras: extras);

    test('a per-track position becomes a book-level one', () {
      final t =
          trackWith({'absStartOffset': 3600.0, 'absBookDuration': 7200.0});
      expect(
        AudiobookProgressService.bookPositionSec(t, const Duration(minutes: 2)),
        3720.0,
      );
    });

    // The whole point of the offset: without it, chapter 5's two-minute mark
    // would be reported as two minutes into the book, rewinding the listener
    // on every other Audiobookshelf client.
    test('an unknown offset yields null so the sync is skipped, not guessed',
        () {
      final t = trackWith({'absBookDuration': 7200.0});
      expect(
          AudiobookProgressService.bookPositionSec(
              t, const Duration(minutes: 2)),
          isNull);
      expect(AudiobookProgressService.startOffsetSec(t), isNull);
    });

    test('the first track starts at zero, which is a real offset not a miss',
        () {
      final t = trackWith({'absStartOffset': 0, 'absBookDuration': 100.0});
      expect(AudiobookProgressService.startOffsetSec(t), 0.0);
      expect(
          AudiobookProgressService.bookPositionSec(
              t, const Duration(seconds: 5)),
          5.0);
    });

    test('book duration is null when absent or zero', () {
      expect(AudiobookProgressService.bookDurationSec(trackWith({})), isNull);
      expect(
          AudiobookProgressService.bookDurationSec(
              trackWith({'absBookDuration': 0})),
          isNull);
    });

    test('session id is null when absent or empty', () {
      expect(AudiobookProgressService.sessionIdOf(trackWith({})), isNull);
      expect(
          AudiobookProgressService.sessionIdOf(trackWith({'absSessionId': ''})),
          isNull);
      expect(
          AudiobookProgressService.sessionIdOf(
              trackWith({'absSessionId': 's1'})),
          's1');
    });

    test('server sync is throttled well below the local save rate', () {
      expect(AudiobookProgressService.serverSyncIntervalMs, greaterThan(5000),
          reason: 'must be slower than the 5s local save');
      expect(AudiobookProgressService.shouldSyncServer(1000, 1000 + 14999),
          isFalse);
      expect(AudiobookProgressService.shouldSyncServer(1000, 1000 + 15000),
          isTrue);
      // A never-synced player has lastSync == 0 while nowMs is epoch millis,
      // so the very first tick syncs immediately rather than waiting 15s.
      expect(
          AudiobookProgressService.shouldSyncServer(
              0, DateTime.now().millisecondsSinceEpoch),
          isTrue);
    });
  });
}
