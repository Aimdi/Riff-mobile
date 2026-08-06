import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';

/// A track shaped exactly like the ones `AudiobookshelfService.toMediaItems`
/// stamps (audiobookshelf_service.dart). Built by hand rather than through the
/// service because `toMediaItems` -> `streamUrl` requires a live connection.
MediaItem absTrack() => MediaItem(
      id: 'abs_bk42_2',
      title: 'Chapter 3',
      album: 'The Book',
      artist: 'An Author',
      duration: const Duration(seconds: 1800),
      artUri: Uri.parse('https://abs.example/api/items/bk42/cover'),
      extras: {
        'url': 'https://abs.example/track3.m4b?token=t',
        'streamSource': 'audiobookshelf',
        'absItemId': 'bk42',
        'absSessionId': 'sess-abc',
        'absTrackIndex': 2,
        'absStartOffset': 3600.0,
        'absBookDuration': 21600.0,
        'album': {'name': 'The Book', 'id': 'bk42'},
        'artists': [
          {'name': 'An Author', 'id': null}
        ],
      },
    );

/// What `saveSessionData` / `_restorePrevSession` do to every queue item:
/// toJson into Hive, fromJson back out on the next launch.
MediaItem roundTrip(MediaItem item) =>
    MediaItemBuilder.fromJson(MediaItemBuilder.toJson(item));

void main() {
  group('MediaItemBuilder session round-trip of Audiobookshelf tracks', () {
    // Regression: toJson/fromJson used fixed key lists that omitted every
    // `abs*` extra. `url` survived, so a restored audiobook still played and
    // the failure was invisible — but sessionId/startOffset/bookDuration were
    // gone, so _syncAudiobookToServer bailed on every tick and the server was
    // never told about anything listened to after the restart.
    test('keeps the keys the server sync depends on', () {
      final restored = roundTrip(absTrack());

      expect(AudiobookProgressService.sessionIdOf(restored), 'sess-abc');
      expect(AudiobookProgressService.bookDurationSec(restored), 21600.0);
      expect(AudiobookProgressService.startOffsetSec(restored), 3600.0);
      // Two minutes into chapter 3 is one hour two minutes into the book.
      expect(
        AudiobookProgressService.bookPositionSec(
            restored, const Duration(minutes: 2)),
        3720.0,
      );
    });

    test('keeps the ids used for local progress records', () {
      final restored = roundTrip(absTrack());

      expect(restored.id, 'abs_bk42_2');
      expect(AudiobookProgressService.isAudiobookItem(restored), isTrue);
      expect(AudiobookProgressService.bookIdOf(restored), 'bk42');
      // Stored on every AudiobookProgressService.save record; was null after
      // a restore.
      expect(restored.extras?['absTrackIndex'], 2);
      expect(restored.extras?['streamSource'], 'audiobookshelf');
      expect(restored.extras?['url'], 'https://abs.example/track3.m4b?token=t');
    });

    // Session data goes through Hive, so the values must survive JSON too.
    test('survives a json encode/decode in between', () {
      final json = jsonDecode(jsonEncode(MediaItemBuilder.toJson(absTrack())));
      final restored = MediaItemBuilder.fromJson(json);

      expect(AudiobookProgressService.sessionIdOf(restored), 'sess-abc');
      expect(AudiobookProgressService.bookDurationSec(restored), 21600.0);
      expect(
        AudiobookProgressService.bookPositionSec(restored, Duration.zero),
        3600.0,
      );
    });

    test('a second round-trip is still stable', () {
      final twice = roundTrip(roundTrip(absTrack()));

      expect(AudiobookProgressService.sessionIdOf(twice), 'sess-abc');
      expect(AudiobookProgressService.startOffsetSec(twice), 3600.0);
      expect(AudiobookProgressService.bookDurationSec(twice), 21600.0);
    });

    // The new keys are conditional, so ordinary songs must serialize exactly
    // as they did before.
    test('leaves non-audiobook items untouched', () {
      const song = MediaItem(
        id: 'dQw4w9WgXcQ',
        title: 'A Song',
        extras: {
          'url': null,
          'length': '3:32',
          'album': null,
          'artists': [
            {'name': 'Someone', 'id': 'UC1'}
          ],
          'date': null,
          'trackDetails': null,
          'year': null,
          'isPodcast': false,
          'description': null,
          'videoType': null,
          'resultType': null,
        },
      );
      final json = MediaItemBuilder.toJson(song);

      for (final k in [
        'streamSource',
        'absItemId',
        'absSessionId',
        'absTrackIndex',
        'absStartOffset',
        'absBookDuration'
      ]) {
        expect(json.containsKey(k), isFalse, reason: '$k must not be emitted');
      }
      final restored = MediaItemBuilder.fromJson(json);
      expect(restored.extras!.containsKey('absItemId'), isFalse);
      expect(AudiobookProgressService.isAudiobookItem(restored), isFalse);
    });
  });
}
