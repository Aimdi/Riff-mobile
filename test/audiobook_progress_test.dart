import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';
import 'package:hive/hive.dart';

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

    test("a free book's chapter without its extras: from the id", () {
      const t = MediaItem(id: 'lv_moby_dick_3', title: 'c');
      expect(AudiobookProgressService.bookIdOf(t), 'moby_dick');
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

  group('a chapter heard to the end', () {
    MediaItem chapter(int i, {String? next, int count = 3}) => MediaItem(
          id: 'lv_moby_$i',
          title: 'Chapter ${i + 1}',
          album: 'Moby Dick',
          artist: 'Herman Melville',
          duration: const Duration(minutes: 30),
          extras: {
            'audiobookId': 'moby',
            'audiobookTrackIndex': i,
            'audiobookTrackCount': count,
            if (next != null) 'audiobookNextId': next,
          },
        );
    void finish(MediaItem m, int at) => AudiobookProgressService.save(
        m, const Duration(minutes: 30), const Duration(minutes: 30),
        nowMs: at);

    setUp(() async {
      await Hive.openBox(AudiobookProgressService.boxName, bytes: Uint8List(0));
    });
    tearDown(Hive.close);

    // Stopped there (sleep timer at the end of a chapter) or a few seconds
    // into the next one: the book used to have no place and started over.
    test('leaves the book at the start of the next chapter', () {
      AudiobookProgressService.save(chapter(0, next: 'lv_moby_1'),
          const Duration(minutes: 10), const Duration(minutes: 30),
          nowMs: 1);
      finish(chapter(0, next: 'lv_moby_1'), 2);
      final last = AudiobookProgressService.lastTrackForBook('moby')!;
      expect(last['id'], 'lv_moby_1');
      expect(last['positionMs'], 0);
      expect(last['trackIndex'], 1);
      expect(last['album'], 'Moby Dick');
      expect(AudiobookProgressService.positionMs('lv_moby_0'), isNull);
    });

    test("a place already kept in the next chapter stays, now the latest", () {
      AudiobookProgressService.save(
          chapter(1), const Duration(minutes: 7), const Duration(minutes: 30),
          nowMs: 1);
      AudiobookProgressService.save(
          chapter(0), const Duration(minutes: 5), const Duration(minutes: 30),
          nowMs: 2);
      finish(chapter(0), 3);
      final last = AudiobookProgressService.lastTrackForBook('moby')!;
      expect(last['id'], 'lv_moby_1');
      expect(last['positionMs'], const Duration(minutes: 7).inMilliseconds);
    });

    test('the last chapter: the book is done, no place kept', () {
      finish(chapter(2), 1);
      expect(AudiobookProgressService.lastTrackForBook('moby'), isNull);
    });

    test('next chapter unknown (saved before Riff kept it): no guess', () {
      const old = MediaItem(
          id: 'abs_bk_4',
          title: 'Chapter 4',
          duration: Duration(minutes: 30),
          extras: {'absItemId': 'bk', 'absTrackIndex': 4});
      finish(old, 1);
      expect(AudiobookProgressService.lastTrackForBook('bk'), isNull);
    });
  });

  test("the chapter after: as the book listed it, else a free book's next", () {
    expect(
        AudiobookProgressService.nextTrackIdOf(const MediaItem(
            id: 'abs_bk_1',
            title: 'c',
            extras: {'audiobookNextId': 'abs_bk_3'})),
        'abs_bk_3');
    expect(
        AudiobookProgressService.nextTrackIdOf(const MediaItem(
            id: 'lv_moby_dick_8',
            title: 'c',
            extras: {'audiobookTrackIndex': 8, 'audiobookTrackCount': 10})),
        'lv_moby_dick_9');
    expect(
        AudiobookProgressService.nextTrackIdOf(const MediaItem(
            id: 'lv_moby_9',
            title: 'c',
            extras: {'audiobookTrackIndex': 9, 'audiobookTrackCount': 10})),
        isNull);
  });
}
