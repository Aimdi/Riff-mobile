import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:harmonymusic/ui/player/lrc_lines.dart';

void main() {
  group('parseLrc', () {
    test('reads timed lines in order and skips tags and blanks', () {
      final lines = parseLrc('''
[ar: Narvent]
[ti: Florescence]
[00:12.50] Do you think about me
[00:09.00]
[00:15.25]Do you miss my pretty my funny my touch
''');
      expect(lines.map((l) => l.text), [
        'Do you think about me',
        'Do you miss my pretty my funny my touch',
      ]);
      expect(lines.first.at, const Duration(seconds: 12, milliseconds: 500));
      expect(lines.last.at, const Duration(seconds: 15, milliseconds: 250));
    });

    test('a line with several stamps appears at each of them', () {
      final lines = parseLrc('[00:10.00][01:20.00] Chorus');
      expect(lines.map((l) => l.at), const [
        Duration(seconds: 10),
        Duration(minutes: 1, seconds: 20),
      ]);
    });

    test('fraction digits: tenths, hundredths, milliseconds', () {
      expect(parseLrc('[00:01.5] a').single.at,
          const Duration(seconds: 1, milliseconds: 500));
      expect(parseLrc('[00:01.05] a').single.at,
          const Duration(seconds: 1, milliseconds: 50));
      expect(parseLrc('[00:01.005] a').single.at,
          const Duration(seconds: 1, milliseconds: 5));
      expect(parseLrc('[00:01] a').single.at, const Duration(seconds: 1));
    });

    test('drops word-timing stamps from the text', () {
      expect(parseLrc('[00:01.00] <00:01.00>Hello <00:01.50>world').single.text,
          'Hello world');
    });
  });

  group('lyricsReaderLrc', () {
    test('every stamp as [mm:ss.mmm]: hundredths and tenths in milliseconds',
        () {
      expect(
          lyricsReaderLrc('[00:05.50] a\n[00:07] b\n[00:08.123] c\n[1:02.5] d'),
          '[00:05.500] a\n[00:07.000] b\n[00:08.123] c\n[01:02.500] d');
    });

    test('a line with two stamps comes twice, in time order', () {
      expect(lyricsReaderLrc('[00:10.00][01:20.00] Chorus\n[00:30.00] Verse'),
          '[00:10.000] Chorus\n[00:30.000] Verse\n[01:20.000] Chorus');
    });

    test('a gap in the singing stays; tags and word stamps go', () {
      expect(
          lyricsReaderLrc(
              '[ar:Someone]\n[00:01.00]<00:01.00>Hel<00:01.50>lo\n[00:04.00]'),
          '[00:01.000]Hello\n[00:04.000]');
    });

    test("the reader's lines start when the LRC says (it read .50 as 50 ms)",
        () {
      final model = LyricsModelBuilder.create()
          .bindLyricToMain(lyricsReaderLrc('[00:05.50] a\n[00:07.05] b'))
          .getModel();
      expect(model.lyrics.map((l) => l.startTime), [5500, 7050]);
    });
  });

  group('lrcLineAt', () {
    final lines = parseLrc('[00:05.00] one\n[00:10.00] two\n[00:20.00] three');

    test('-1 before the first line', () {
      expect(lrcLineAt(lines, Duration.zero), -1);
      expect(lrcLineAt(lines, const Duration(seconds: 4)), -1);
    });

    test('the latest line that has started', () {
      expect(lrcLineAt(lines, const Duration(seconds: 5)), 0);
      expect(lrcLineAt(lines, const Duration(seconds: 12)), 1);
      expect(lrcLineAt(lines, const Duration(minutes: 3)), 2);
    });

    test('empty lyrics', () {
      expect(lrcLineAt(const [], const Duration(seconds: 3)), -1);
    });
  });
}
