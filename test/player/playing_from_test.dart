import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playling_from.dart';

void main() {
  group('PlaylingFrom.canOpen', () {
    test('albums, playlists and artists with an id open', () {
      for (final type in [
        PlaylingFromType.ALBUM,
        PlaylingFromType.PLAYLIST,
        PlaylingFromType.ARTIST,
      ]) {
        expect(PlaylingFrom(type: type, name: 'x', id: 'id1').canOpen, isTrue,
            reason: '$type');
      }
    });

    test('a selection, or a source without an id, does not', () {
      expect(PlaylingFrom(type: PlaylingFromType.SELECTION, id: 'id1').canOpen,
          isFalse);
      expect(PlaylingFrom(type: PlaylingFromType.ALBUM, name: 'x').canOpen,
          isFalse);
      expect(PlaylingFrom(type: PlaylingFromType.PLAYLIST).canOpen, isFalse);
    });
  });

  group('a saved session keeps it', () {
    test('its kind, name and id come back; not the page model', () {
      final from = PlaylingFrom.fromJson(PlaylingFrom(
              type: PlaylingFromType.PLAYLIST,
              name: 'Sleep',
              id: 'LIB1',
              item: Object())
          .toJson());
      expect(from.type, PlaylingFromType.PLAYLIST);
      expect(from.name, 'Sleep');
      expect(from.id, 'LIB1');
      expect(from.item, isNull);
      expect(from.canOpen, isTrue);
    });

    test('a session saved without it, or garbled, is a selection', () {
      for (final saved in [
        null,
        'PLAYLIST',
        {'type': 'MIXTAPE', 'id': 'x'},
        {'name': 'Sleep'},
      ]) {
        final from = PlaylingFrom.fromJson(saved);
        expect(from.type, PlaylingFromType.SELECTION, reason: '$saved');
        expect(from.canOpen, isFalse, reason: '$saved');
      }
    });
  });
}
