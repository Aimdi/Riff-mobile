import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/show_notes_links.dart';
import 'package:harmonymusic/ui/player/components/show_notes_text.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

void main() {
  test('timestamps and links are picked out of the notes', () {
    expect(
        showNotesParts('00:00 Intro\n12:34 Interview\n1:02:03 Outro, '
            'notes at https://example.com/notes. Bye'),
        const [
          ShowNotesPart.time('00:00', 0),
          ShowNotesPart.text(' Intro\n'),
          ShowNotesPart.time('12:34', 754),
          ShowNotesPart.text(' Interview\n'),
          ShowNotesPart.time('1:02:03', 3723),
          ShowNotesPart.text(' Outro, notes at '),
          ShowNotesPart.link(
              'https://example.com/notes', 'https://example.com/notes'),
          ShowNotesPart.text('. Bye'),
        ]);
  });

  test('not timestamps: versions, decimals, impossible times', () {
    expect(showNotesParts('v1.2:30, 3.12:45, 99:99 and 1:75:00'),
        const [ShowNotesPart.text('v1.2:30, 3.12:45, 99:99 and 1:75:00')]);
  });

  test('past the episode: a clock time, not a moment of it', () {
    expect(
        showNotesParts('5:07 and 61:30', length: const Duration(minutes: 30)),
        const [
          ShowNotesPart.time('5:07', 307),
          ShowNotesPart.text(' and 61:30'),
        ]);
    // Length unknown: any valid timestamp counts.
    expect(showNotesParts('61:30'), const [ShowNotesPart.time('61:30', 3690)]);
  });

  test('a link in brackets stops at the bracket', () {
    expect(showNotesParts('(https://a.example/b?c=1)'), const [
      ShowNotesPart.text('('),
      ShowNotesPart.link('https://a.example/b?c=1', 'https://a.example/b?c=1'),
      ShowNotesPart.text(')'),
    ]);
  });

  testWidgets('a tap on a timestamp plays from there, on a link opens it',
      (tester) async {
    final times = <int>[];
    final links = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: ShowNotesText(
          notes: 'Jump to 12:34, or read https://example.com',
          onTime: times.add,
          onLink: links.add,
        ),
      ),
    ));
    final text = tester.widget<RichText>(find.byType(RichText).first).text;
    final spans = <TextSpan>[];
    text.visitChildren((span) {
      if (span is TextSpan) spans.add(span);
      return true;
    });
    TapGestureRecognizer tapOf(String part) =>
        spans.firstWhere((s) => s.text == part).recognizer!
            as TapGestureRecognizer;

    tapOf('12:34').onTap!();
    tapOf('https://example.com').onTap!();
    expect(times, [754]);
    expect(links, ['https://example.com']);
    // Plain text has no tap.
    expect(spans.firstWhere((s) => s.text == 'Jump to ').recognizer, isNull);
  });
}
