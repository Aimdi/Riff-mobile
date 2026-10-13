import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/cover_palette.dart';
import 'package:harmonymusic/ui/player/components/lyrics_share.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

const _song = MediaItem(id: 'song1', title: 'Song A', artist: 'Artist A');

void main() {
  group('lyricLinesForSharing', () {
    test('LRC: times and tags go, blank lines too', () {
      const lrc = '[ti:Song A]\n[ar:Artist A]\n[00:12.34]Hello there\n'
          '[00:15.00][01:20.00]Chorus line\n\n[00:20.00]\n';
      expect(lyricLinesForSharing(synced: lrc), ['Hello there', 'Chorus line']);
    });

    test('plain lyrics, or none', () {
      expect(lyricLinesForSharing(plain: 'Line one\r\n\nLine two'),
          ['Line one', 'Line two']);
      expect(lyricLinesForSharing(plain: 'NA'), isEmpty);
      expect(lyricLinesForSharing(), isEmpty);
    });

    test('word-synced lyrics come first', () {
      const ttml = '<p begin="1.0" end="2.0"><span begin="1.0" end="1.5">One'
          '</span></p><p begin="2.0" end="3.0">Two</p>';
      expect(
          lyricLinesForSharing(
              ttml: ttml, synced: '[00:01.00]Other', plain: 'Plain'),
          ['One', 'Two']);
    });
  });

  Widget host(Widget child) => MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(body: child),
      );

  testWidgets('the card shows the song and the picked lines', (tester) async {
    await tester.pumpWidget(host(Center(
      child: LyricsShareCard(
        song: _song,
        lines: const ['First line', 'Second line'],
        palette: coverPaletteFrom(dominant: const Color(0xFF1DB954)),
      ),
    )));
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Artist A'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
  });

  testWidgets('lines are picked up to the limit, in song order',
      (tester) async {
    // A phone-sized screen, so the whole list is laid out.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final lines = [for (var i = 0; i < 8; i++) 'Line $i'];
    await tester.pumpWidget(host(LyricsShareSheet(song: _song, lines: lines)));

    List<String> card() =>
        tester.widget<LyricsShareCard>(find.byType(LyricsShareCard)).lines;
    // In the list (after the card), scrolled into view, then tapped.
    Future<void> tapLine(int i) async {
      await tester.ensureVisible(find.text('Line $i').last);
      await tester.pump();
      await tester.tap(find.text('Line $i').last);
      await tester.pump();
    }

    // The first line starts picked, so the card is never empty.
    expect(card(), ['Line 0']);

    for (final i in [3, 1, 2, 4, 5, 6]) {
      await tapLine(i);
    }
    // Five at most, in song order: 5 and 6 didn't fit.
    expect(card(), ['Line 0', 'Line 1', 'Line 2', 'Line 3', 'Line 4']);

    // Tapping a picked line drops it.
    await tapLine(3);
    expect(card(), ['Line 0', 'Line 1', 'Line 2', 'Line 4']);
  });
}
