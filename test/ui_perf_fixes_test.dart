import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/better_lyrics_service.dart';
import 'package:harmonymusic/services/podcast_progress_service.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/player/components/podcast_transcript_sheet.dart';
import 'package:harmonymusic/ui/player/components/word_synced_lyrics.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:harmonymusic/ui/widgets/header_hero_fade.dart';
import 'package:harmonymusic/ui/widgets/mini_player_progress_bar.dart';

void main() {
  group('PaletteRequestGate', () {
    test('dedupes repeated requests for the same song', () {
      final g = PaletteRequestGate();
      expect(g.begin('a'), isTrue);
      expect(g.begin('a'), isFalse, reason: 'already in flight');
      expect(g.complete('a'), isTrue);
      expect(g.current, 'a');
      expect(g.begin('a'), isFalse, reason: 'already applied');
    });

    test('drops a stale result that finishes after a newer request', () {
      final g = PaletteRequestGate();
      g.begin('old');
      g.begin('new');
      expect(g.complete('old'), isFalse);
      expect(g.current, isNull);
      expect(g.complete('new'), isTrue);
      expect(g.current, 'new');
    });

    test('failure allows a retry', () {
      final g = PaletteRequestGate();
      g.begin('a');
      g.fail('a');
      expect(g.begin('a'), isTrue);
    });
  });

  test('mini player progress painter moves with each tick, only then', () {
    ProgressBarPainter p(int ms, {int totalMs = 200000}) => ProgressBarPainter(
          current: Duration(milliseconds: ms),
          total: Duration(milliseconds: totalMs),
          progressBarColor: Colors.green,
        );
    // Smooth: a sub-second tick moves the line (it used to wait for the
    // next whole second).
    expect(p(10100).shouldRepaint(p(10000)), isTrue);
    expect(p(11000).shouldRepaint(p(10900)), isTrue);
    // A tick that didn't move it doesn't repaint.
    expect(p(10000).shouldRepaint(p(10000)), isFalse);
    expect(p(10000, totalMs: 1000).shouldRepaint(p(10000)), isTrue);
  });

  test('mini player progress line is drawn to the millisecond', () {
    final recorder = PictureRecorder();
    final canvas = _LineCanvas(Canvas(recorder));
    ProgressBarPainter(
      current: const Duration(milliseconds: 1500),
      total: const Duration(seconds: 3),
      progressBarColor: Colors.green,
    ).paint(canvas, const Size(300, 2));
    recorder.endRecording();
    expect(canvas.end?.dx, closeTo(150, 1e-9));
  });

  test('wordSyncedActiveLine picks the last started line', () {
    final lines = [
      const TtmlLine(beginSec: 0, text: 'a'),
      const TtmlLine(beginSec: 5, text: 'b'),
      const TtmlLine(beginSec: 9, text: 'c'),
    ];
    expect(wordSyncedActiveLine(lines, 0), 0);
    expect(wordSyncedActiveLine(lines, 4.9), 0);
    expect(wordSyncedActiveLine(lines, 5), 1);
    expect(wordSyncedActiveLine(lines, 100), 2);
    expect(wordSyncedActiveLine(const [], 3), 0);
  });

  test('transcriptActiveIndex matches the linear scan with or without hint',
      () {
    final cues = [
      for (final s in [1.0, 4.0, 8.0, 12.0])
        PodcastTranscriptCue(startSec: s, text: 't$s'),
    ];
    for (final pos in [0.0, 1.0, 3.9, 4.0, 7.0, 8.5, 12.0, 99.0]) {
      final expected = transcriptActiveIndex(cues, pos);
      for (var hint = -1; hint < cues.length; hint++) {
        expect(transcriptActiveIndex(cues, pos, hint: hint), expected,
            reason: 'pos=$pos hint=$hint');
      }
    }
    expect(transcriptActiveIndex(cues, 0.5), -1);
    expect(transcriptActiveIndex(cues, 9), 2);
  });

  test('newestProgressRow returns the max updatedAt row', () {
    expect(PodcastProgressService.newestProgressRow(const []), isNull);
    final row = PodcastProgressService.newestProgressRow([
      {'id': 'a', 'updatedAt': 5},
      'junk',
      {'id': 'b', 'updatedAt': 9},
      {'id': 'c'},
    ]);
    expect(row?['id'], 'b');
  });

  testWidgets('HeaderHeroFade paints and fades without errors',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: HeaderHeroFade(
        opacity: 0.4,
        color: Colors.black,
        leftShadowOffset: -800,
        bottomShadowOffset: 480,
        child: SizedBox(width: 400, height: 400),
      ),
    ));
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, closeTo(0.4, 1e-9));
    expect(tester.takeException(), isNull);
  });
}

/// Records where a painter's line ends.
class _LineCanvas implements Canvas {
  _LineCanvas(this._inner);
  final Canvas _inner;
  Offset? end;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    end = p2;
    _inner.drawLine(p1, p2, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
