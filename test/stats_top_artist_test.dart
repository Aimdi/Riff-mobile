import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/stats_service.dart';

void main() {
  test('podcasts and audiobooks never rank as the top artist', () {
    final rows = {
      // A YouTube episode the feed gave the placeholder artist "Podcast".
      'ytEp1': {'artist': 'Podcast', 'plays': 40, 'lastSource': 'home'},
      // RSS episode, LibriVox and Audiobookshelf chapters by id.
      'podcast_abc': {'artist': 'The Daily', 'plays': 30},
      'lv_123_0': {'artist': 'Jane Austen', 'plays': 25},
      'abs_book_2': {'artist': 'Narrator', 'plays': 25},
      // Played from the podcast player, or stored with its kind.
      'ytEp2': {'artist': 'Huberman Lab', 'plays': 22, 'lastSource': 'podcast'},
      'ytEp3': {'artist': 'Lex Fridman', 'plays': 21, 'kind': 'podcast'},
      // Music.
      's1': {'artist': 'Rammstein', 'plays': 12},
      's2': {'artist': 'Rammstein', 'plays': 3},
      's3': {'artist': 'Daft Punk', 'plays': 9},
      's4': {'artist': '', 'plays': 99},
    };
    final top = rankTopArtists(rows, 5);
    expect(top.first, {'artist': 'Rammstein', 'plays': 15});
    expect(top.map((r) => r['artist']), ['Rammstein', 'Daft Punk']);
  });

  test('nothing but podcasts: no top artist at all', () {
    expect(
        rankTopArtists({
          'x': {'artist': 'podcast', 'plays': 3}
        }),
        isEmpty);
  });

  test('isNonMusicStat reads kind, id, source and placeholder artist', () {
    expect(isNonMusicStat('a', {'kind': 'audiobook'}), isTrue);
    expect(isNonMusicStat('podcast_1', {}), isTrue);
    expect(isNonMusicStat('a', {'lastSource': 'audiobook'}), isTrue);
    expect(isNonMusicStat('a', {'artist': ' Podcast '}), isTrue);
    expect(isNonMusicStat('a', {'artist': 'Podcasts & Chill Band'}), isFalse);
  });
}
