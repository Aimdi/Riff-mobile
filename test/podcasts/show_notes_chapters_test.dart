import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_segments.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/services/show_notes_chapters.dart';

List<(double, String)> _chapters(String notes, {Duration? length}) => [
      for (final c in showNotesChapters(notes, length: length))
        (c.startSec, c.title),
    ];

void main() {
  test('a list of the parts by their start, however it is written', () {
    const notes = '''
This week: a long talk with Ada about engines.

Timestamps:
00:00 Intro
(04:12) The interview
• [12:30] – Listener mail
1:02:03 - Wrap-up
Thanks to our sponsors!''';
    expect(_chapters(notes), [
      (0.0, 'Intro'),
      (252.0, 'The interview'),
      (750.0, 'Listener mail'),
      (3723.0, 'Wrap-up'),
    ]);
  });

  test('timestamps after the titles', () {
    expect(_chapters('Intro (0:00)\nThe interview - 4:12\nWrap-up 58:01'), [
      (0.0, 'Intro'),
      (252.0, 'The interview'),
      (3481.0, 'Wrap-up'),
    ]);
  });

  test('a linked title keeps its words', () {
    expect(
        _chapters('00:00 [Intro](https://example.com/a)\n'
            '05:00 Main topic\n'
            '20:00 — Outro –'),
        [(0.0, 'Intro'), (300.0, 'Main topic'), (1200.0, 'Outro')]);
  });

  test("not a list of the episode's parts", () {
    // Fewer than three.
    expect(_chapters('00:00 Intro\n10:00 Outro'), isEmpty);
    // Times in the text.
    expect(
        _chapters('We start at 5:00 sharp.\nAt 12:30 Ada joins us.\n'
            'The live show airs at 9:30.'),
        isEmpty);
    // Out of order.
    expect(_chapters('10:00 B\n05:00 A\n20:00 C'), isEmpty);
    // Too close together: not parts.
    expect(_chapters('00:00 A\n00:05 B\n00:30 C'), isEmpty);
    // Past the episode's end.
    expect(
        _chapters('00:00 A\n10:00 B\n50:00 C',
            length: const Duration(minutes: 30)),
        isEmpty);
    // Timestamps with nothing to say.
    expect(_chapters('00:00\n10:00\n20:00'), isEmpty);
    // 00:61 isn't a time: two are left.
    expect(_chapters('00:61 A\n10:00 B\n20:00 C'), isEmpty);
  });

  test('a list in the opening form wins over a stray time at a line end', () {
    expect(
        _chapters('Recorded live, doors at 7:30\n'
            '00:00 Welcome\n'
            '03:00 First song\n'
            '09:30 Q&A'),
        [(0.0, 'Welcome'), (180.0, 'First song'), (570.0, 'Q&A')]);
  });

  test('within the length when it is known', () {
    expect(
        _chapters('00:00 A\n10:00 B\n20:00 C',
            length: const Duration(minutes: 30)),
        hasLength(3));
  });

  test("nothing skips on its own by the notes' times", () {
    // Ads put in as the episode is fetched can move the audio away from
    // the notes: their "Sponsor" part isn't skipped by itself.
    final fromNotes = showNotesChapters('00:00 Intro\n'
        '01:00 Sponsor: Acme\n'
        '02:00 The interview');
    expect(fromNotes.every((c) => c.fromNotes), isTrue);
    expect(segmentsFromChapters(fromNotes, 3600), isEmpty);
    // The feed's own chapters are, as before.
    final fromFeed = [
      PodcastChapter(startSec: 0, title: 'Intro'),
      PodcastChapter(startSec: 60, title: 'Sponsor: Acme'),
      PodcastChapter(startSec: 120, title: 'The interview'),
    ];
    expect(segmentsFromChapters(fromFeed, 3600).map((s) => s.category),
        contains(SegmentCategory.sponsor));
  });
}
