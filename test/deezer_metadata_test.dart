import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/deezer_metadata_service.dart';

void main() {
  group('buildQuery', () {
    test('quotes each field so multi-word titles are not split', () {
      expect(
        DeezerMetadataService.buildQuery('Bohemian Rhapsody', 'Queen'),
        'track:"Bohemian Rhapsody" artist:"Queen"',
      );
    });

    // Deezer indexes the primary artist; a joined "A, B, C" string matches
    // nothing, which would silently return no enrichment for every
    // collaboration.
    test('uses only the first credited artist', () {
      expect(
        DeezerMetadataService.buildQuery('Song', 'Alan Walker, Iselin Solheim'),
        'track:"Song" artist:"Alan Walker"',
      );
      expect(
        DeezerMetadataService.buildQuery('Song', 'A & B'),
        'track:"Song" artist:"A"',
      );
      expect(
        DeezerMetadataService.buildQuery('Song', 'Main feat. Guest'),
        'track:"Song" artist:"Main"',
      );
    });

    test('falls back to a track-only query when no artist is known', () {
      expect(DeezerMetadataService.buildQuery('Song', ''), 'track:"Song"');
    });

    // Spotify subtitles separate artists with non-breaking spaces.
    test('normalises non-breaking spaces and stray quotes', () {
      expect(
        DeezerMetadataService.buildQuery('A B', 'Artist'),
        'track:"A B" artist:"Artist"',
      );
      expect(
        DeezerMetadataService.buildQuery('He said "hi"', 'Artist'),
        'track:"He said hi" artist:"Artist"',
      );
    });
  });

  group('parseFirstResult', () {
    test('reads title, artist, album and converts seconds to milliseconds', () {
      const body = '''
      {"data":[{"title":"Bohemian Rhapsody","title_short":"Bohemian Rhapsody",
      "duration":354,"artist":{"name":"Queen"},"album":{"title":"A Night at the Opera"}}]}
      ''';
      final m = DeezerMetadataService.parseFirstResult(body)!;
      expect(m.title, 'Bohemian Rhapsody');
      expect(m.artist, 'Queen');
      expect(m.album, 'A Night at the Opera');
      expect(m.durationMs, 354000);
    });

    test('prefers title_short, which omits the version suffix', () {
      const body = '''
      {"data":[{"title":"Song (Remastered 2011)","title_short":"Song",
      "duration":200,"artist":{"name":"A"}}]}
      ''';
      expect(DeezerMetadataService.parseFirstResult(body)!.title, 'Song');
    });

    // Every one of these must return null rather than throw: enrichment runs
    // inside the import loop and must never break an import.
    test('returns null for misses, errors and malformed payloads', () {
      for (final body in <String>[
        '{"data":[]}',
        '{"error":{"type":"Exception","message":"Quota limit exceeded"}}',
        'not json at all',
        '[]',
        '{"data":[{}]}',
        '{"data":["nonsense"]}',
      ]) {
        expect(DeezerMetadataService.parseFirstResult(body), isNull,
            reason: 'should not throw or match on: $body');
      }
    });

    test('treats a zero or missing duration as unknown, not as zero', () {
      const zero =
          '{"data":[{"title":"S","duration":0,"artist":{"name":"A"}}]}';
      const missing = '{"data":[{"title":"S","artist":{"name":"A"}}]}';
      expect(DeezerMetadataService.parseFirstResult(zero)!.durationMs, isNull);
      expect(
          DeezerMetadataService.parseFirstResult(missing)!.durationMs, isNull);
    });

    test('tolerates a missing artist object', () {
      const body = '{"data":[{"title":"S","duration":100}]}';
      final m = DeezerMetadataService.parseFirstResult(body)!;
      expect(m.artist, '');
      expect(m.durationMs, 100000);
    });
  });
}
