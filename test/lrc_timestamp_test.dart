import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/better_lyrics_service.dart';
import 'package:harmonymusic/services/synced_lyrics_service.dart';

void main() {
  group('SyncedLyricsService.normalizeLrcTimestamps', () {
    // flutter_lyric parses [mm:ss.47] as 47ms (not 470ms); 3-digit stamps
    // take its correct branch. These tests pin the normalization contract.
    test('pads 2-digit centisecond stamps to milliseconds', () {
      expect(
        SyncedLyricsService.normalizeLrcTimestamps('[00:03.47]line'),
        '[00:03.470]line',
      );
    });

    test('pads 1-digit decisecond stamps', () {
      expect(
        SyncedLyricsService.normalizeLrcTimestamps('[01:02.5]line'),
        '[01:02.500]line',
      );
    });

    test('leaves 3-digit stamps untouched (idempotent)', () {
      const lrc = '[00:03.470]line';
      expect(SyncedLyricsService.normalizeLrcTimestamps(lrc), lrc);
      expect(
        SyncedLyricsService.normalizeLrcTimestamps(
            SyncedLyricsService.normalizeLrcTimestamps('[00:03.47]x')),
        '[00:03.470]x',
      );
    });

    test('handles multiple stamps and full documents', () {
      const input = '[00:01.10][00:02.2]repeated\n[12:34.56]later';
      expect(
        SyncedLyricsService.normalizeLrcTimestamps(input),
        '[00:01.100][00:02.200]repeated\n[12:34.560]later',
      );
    });
  });

  group('BetterLyricsService.formatTimestamp', () {
    test('emits 3 fractional digits', () {
      expect(BetterLyricsService.formatTimestamp(3.47), '00:03.470');
      expect(BetterLyricsService.formatTimestamp(62.5), '01:02.500');
      expect(BetterLyricsService.formatTimestamp(0), '00:00.000');
    });
  });
}
