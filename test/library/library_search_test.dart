import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Library/library_search.dart';

void main() {
  group('foldForSearch', () {
    test('lower-cases and drops accents', () {
      expect(foldForSearch('Beyoncé'), 'beyonce');
      expect(foldForSearch('MØ – Ñandú'), 'mo – nandu');
      expect(foldForSearch('Straße'), 'strasse');
    });
  });

  group('libraryMatches', () {
    test('every word must appear somewhere', () {
      final fields = ['Get Lucky', 'Daft Punk', 'Random Access Memories'];
      expect(libraryMatches('daft lucky', fields), isTrue);
      expect(libraryMatches('random memories', fields), isTrue);
      expect(libraryMatches('daft nope', fields), isFalse);
    });

    test('ignores case, accents and extra spaces', () {
      expect(libraryMatches('  BEYONCE   halo ', ['Halo', 'Beyoncé']), isTrue);
      expect(libraryMatches('café', ['Cafe del Mar']), isTrue);
    });

    test('an empty query matches everything', () {
      expect(libraryMatches('', ['x']), isTrue);
      expect(libraryMatches('   ', ['x']), isTrue);
    });

    test('a word does not match across two fields', () {
      // "lucky" ends the title and "daft" starts the artist; glued
      // together they must not count as one word.
      expect(libraryMatches('luckydaft', ['Get Lucky', 'Daft Punk']), isFalse);
    });

    test('missing fields are skipped', () {
      expect(libraryMatches('mix', [null, 'Morning mix', null]), isTrue);
    });
  });

  group('songSearchFields', () {
    test('title, artist and album, including the album map from YouTube', () {
      const song = MediaItem(
        id: 'x',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        extras: {
          'album': {'name': 'Random Access Memories', 'id': 'MPRE1'}
        },
      );
      expect(libraryMatches('memories', songSearchFields(song)), isTrue);
      expect(libraryMatches('daft', songSearchFields(song)), isTrue);
    });
  });
}
