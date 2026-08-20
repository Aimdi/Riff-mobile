import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_item_extras.dart';

MediaItem _item({
  String id = 'vid',
  Map<String, dynamic>? extras,
}) =>
    MediaItem(id: id, title: 't', extras: extras);

void main() {
  group('MediaItemExtras', () {
    test('reads typed extras without throwing on missing keys', () {
      final song = _item();
      expect(song.extrasUrl, isNull);
      expect(song.discoverySourceWire, isNull);
      expect(song.chaptersUrl, isNull);
      expect(song.absSessionId, isNull);
      expect(song.absStartOffsetSec, 0);
      expect(song.isPodcastEpisode, isFalse);
      expect(song.isAudiobookshelf, isFalse);
      expect(song.extrasArtists, isEmpty);
    });

    test('podcast and audiobook flags from extras or id prefix', () {
      expect(_item(id: 'podcast_1').isPodcastEpisode, isTrue);
      expect(
        _item(extras: {'isPodcast': true}).isPodcastEpisode,
        isTrue,
      );
      expect(_item(id: 'abs_book').isAudiobookshelf, isTrue);
      expect(
        _item(extras: {'streamSource': 'audiobookshelf'}).isAudiobookshelf,
        isTrue,
      );
    });

    test('numeric extras accept int, double, and string', () {
      expect(
        _item(extras: {'absStartOffsetSec': 12}).absStartOffsetSec,
        12,
      );
      expect(
        _item(extras: {'absStartOffsetSec': 3.5}).absStartOffsetSec,
        3.5,
      );
      expect(
        _item(extras: {'absStartOffsetSec': '8'}).absStartOffsetSec,
        8,
      );
    });

    test('artists list skips non-maps', () {
      final song = _item(extras: {
        'artists': [
          {'id': 'a1', 'name': 'A'},
          'nope',
          {'id': 'a2'},
        ],
      });
      expect(song.extrasArtists.length, 2);
      expect(song.extrasArtists.first['id'], 'a1');
    });

    test('mediaItemIds drops blanks and duplicates', () {
      expect(
        mediaItemIds([
          _item(id: 'a'),
          _item(id: 'a'),
          _item(id: ''),
          _item(id: 'b'),
        ]),
        {'a', 'b'},
      );
    });
  });
}
