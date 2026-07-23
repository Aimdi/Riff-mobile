import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/soulseek/soulseek_client.dart';
import 'package:harmonymusic/services/soulseek/soulseek_search.dart';

SoulseekFile _file({
  required String user,
  required String path,
  bool slot = true,
  int? br = 320,
  int size = 8000000,
  int speed = 200000,
}) {
  return SoulseekFile(
    username: user,
    filename: path,
    size: size,
    hasFreeSlot: slot,
    speed: speed,
    bitRate: br,
    lengthSeconds: 200,
  );
}

void main() {
  group('SoulseekQuery', () {
    test('parses Artist - Title shorthand for song mode', () {
      final q = SoulseekQuery.parse('Radiohead - Creep', SoulseekSearchMode.song);
      expect(q.artist, 'Radiohead');
      expect(q.title, 'Creep');
      expect(q.networkQuery, 'Radiohead Creep');
    });

    test('parses Artist - Album for album mode', () {
      final q = SoulseekQuery.parse(
        'Daft Punk - Random Access Memories',
        SoulseekSearchMode.album,
      );
      expect(q.artist, 'Daft Punk');
      expect(q.title, 'Random Access Memories');
      expect(q.mode, SoulseekSearchMode.album);
    });

    test('parses keyed artist/title', () {
      final q = SoulseekQuery.parse(
        'artist=Bjork, title=Hyperballad',
        SoulseekSearchMode.song,
      );
      expect(q.artist, 'Bjork');
      expect(q.title, 'Hyperballad');
    });

    test('bare string becomes title', () {
      final q = SoulseekQuery.parse('hyperballad', SoulseekSearchMode.song);
      expect(q.artist, isNull);
      expect(q.title, 'hyperballad');
      expect(q.networkQuery, 'hyperballad');
    });
  });

  group('SoulseekSearchRanker', () {
    const ranker = SoulseekSearchRanker();
    final query = SoulseekQuery.parse(
      'Artist - Song',
      SoulseekSearchMode.song,
    );
    const filters = SoulseekSearchFilters();

    test('ranks free-slot FLAC with matching path highest', () {
      final hits = [
        _file(
          user: 'a',
          path: r'@@a\misc\other.mp3',
          slot: false,
          br: 128,
        ),
        _file(
          user: 'b',
          path: r'@@b\Music\Artist\Song.flac',
          slot: true,
          br: 0,
        ),
        _file(
          user: 'c',
          path: r'@@c\Artist - Song.mp3',
          slot: true,
          br: 320,
        ),
      ];
      final ranked = ranker.rankFiles(hits, query, filters);
      expect(ranked.first.file.username, anyOf('b', 'c'));
      expect(ranked.first.file.hasFreeSlot, isTrue);
      expect(ranked.last.file.username, 'a');
    });

    test('format filter excludes non-matching extensions', () {
      final hits = [
        _file(user: 'a', path: r'x\Song.flac'),
        _file(user: 'b', path: r'x\Song.mp3'),
      ];
      final ranked = ranker.rankFiles(
        hits,
        query,
        const SoulseekSearchFilters(formats: {'flac'}),
      );
      expect(ranked.length, 1);
      expect(ranked.first.file.extension, 'flac');
    });

    test('groups album folders and ranks by score', () {
      final albumQuery = SoulseekQuery.parse(
        'Artist - Cool Album',
        SoulseekSearchMode.album,
      );
      final hits = [
        _file(user: 'u1', path: r'@@u1\Cool Album\01.flac'),
        _file(user: 'u1', path: r'@@u1\Cool Album\02.flac'),
        _file(user: 'u1', path: r'@@u1\Cool Album\03.flac'),
        _file(user: 'u2', path: r'@@u2\Other\track.mp3', slot: false),
        _file(user: 'u2', path: r'@@u2\Other\track2.mp3', slot: false),
      ];
      final folders = ranker.groupAlbums(hits, albumQuery, filters);
      expect(folders, isNotEmpty);
      expect(folders.first.folderName, 'Cool Album');
      expect(folders.first.trackCount, 3);
    });
  });

  test('SoulseekFile folder helpers', () {
    final hit = _file(
      user: 'alice',
      path: r'@@alice\Music\Cool Album\Song.flac',
    );
    expect(hit.displayName, 'Song.flac');
    expect(hit.folderName, 'Cool Album');
    expect(hit.folderPath, '@@alice/Music/Cool Album');
  });
}
