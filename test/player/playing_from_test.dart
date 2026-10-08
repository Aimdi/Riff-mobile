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
}
