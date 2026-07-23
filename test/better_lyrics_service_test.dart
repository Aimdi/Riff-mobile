import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/better_lyrics_service.dart';

void main() {
  group('BetterLyricsService.ttmlToLrc', () {
    test('converts line begin timestamps and strips span tags', () {
      const ttml = '''
<p begin="9.731" end="12.105" itunes:key="L1">
<span begin="9.731" end="9.927">The</span>
<span begin="9.927" end="10.284">club</span>
</p>
<p begin="1:02.5" end="1:05.0"><span>Hello</span> world</p>
''';
      final lrc = BetterLyricsService.ttmlToLrc(ttml);
      expect(lrc, isNotNull);
      expect(lrc, contains('[00:09.73]The club'));
      expect(lrc, contains('[01:02.50]Hello world'));
    });

    test('returns null when no timed lines', () {
      expect(BetterLyricsService.ttmlToLrc('<tt></tt>'), isNull);
    });

    test('ttmlToPlain drops timestamps', () {
      const ttml =
          '<p begin="1.0" end="2.0"><span>One</span></p><p begin="2.0" end="3.0">Two</p>';
      expect(BetterLyricsService.ttmlToPlain(ttml), 'One\nTwo');
    });
  });

  test('LyricsSource enum order is stable for Hive indexes', () {
    expect(LyricsSource.auto.index, 0);
    expect(LyricsSource.betterLyrics.index, 1);
    expect(LyricsSource.lrclib.index, 2);
  });
}
