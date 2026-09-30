import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/podcast_service.dart';

int utc(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, mo, d, h, mi, s).millisecondsSinceEpoch;

void main() {
  group('pubDateMs (RFC 822/2822)', () {
    final cases = <String, int>{
      // Literal GMT (the only form HttpDate.parse accepted).
      'Sat, 19 Jul 2026 08:00:00 GMT': utc(2026, 7, 19, 8),
      // Numeric offsets.
      'Sat, 19 Jul 2026 08:00:00 +0000': utc(2026, 7, 19, 8),
      'Sat, 19 Jul 2026 08:00:00 -0500': utc(2026, 7, 19, 13),
      'Sat, 19 Jul 2026 08:00:00 +0530': utc(2026, 7, 19, 2, 30),
      'Sat, 19 Jul 2026 08:00:00 +02:00': utc(2026, 7, 19, 6),
      // US zone names.
      'Sat, 19 Jul 2026 08:00:00 EST': utc(2026, 7, 19, 13),
      'Sat, 19 Jul 2026 08:00:00 EDT': utc(2026, 7, 19, 12),
      'Sat, 19 Jul 2026 08:00:00 CST': utc(2026, 7, 19, 14),
      'Sat, 19 Jul 2026 08:00:00 CDT': utc(2026, 7, 19, 13),
      'Sat, 19 Jul 2026 08:00:00 MST': utc(2026, 7, 19, 15),
      'Sat, 19 Jul 2026 08:00:00 MDT': utc(2026, 7, 19, 14),
      'Sat, 19 Jul 2026 08:00:00 PST': utc(2026, 7, 19, 16),
      'Sat, 19 Jul 2026 08:00:00 PDT': utc(2026, 7, 19, 15),
      'Sat, 19 Jul 2026 08:00:00 UT': utc(2026, 7, 19, 8),
      'Sat, 19 Jul 2026 08:00:00 UTC': utc(2026, 7, 19, 8),
      'Sat, 19 Jul 2026 08:00:00 Z': utc(2026, 7, 19, 8),
      // Military / unknown zones read as UTC.
      'Sat, 19 Jul 2026 08:00:00 A': utc(2026, 7, 19, 8),
      'Sat, 19 Jul 2026 08:00:00 XYZ': utc(2026, 7, 19, 8),
      // No zone at all.
      'Sat, 19 Jul 2026 08:00:00': utc(2026, 7, 19, 8),
      // No weekday.
      '19 Jul 2026 08:00:00 +0000': utc(2026, 7, 19, 8),
      // Weekday without comma.
      'Sat 19 Jul 2026 08:00:00 +0000': utc(2026, 7, 19, 8),
      // No seconds.
      'Sat, 19 Jul 2026 08:00 -0700': utc(2026, 7, 19, 15),
      // Single-digit day and hour.
      'Wed, 1 Jul 2026 8:05:09 +0000': utc(2026, 7, 1, 8, 5, 9),
      // Full month name, 2-digit year.
      'Sun, 5 July 26 10:00:00 GMT': utc(2026, 7, 5, 10),
      // Date only.
      '19 Jul 2026': utc(2026, 7, 19),
      // Lower-case month and extra whitespace.
      '  Sat,  19 jul 2026 08:00:00 +0000 ': utc(2026, 7, 19, 8),
      // Leap second clamps rather than rolling over.
      'Sat, 19 Jul 2026 23:59:60 +0000': utc(2026, 7, 19, 23, 59, 59),
      // ISO 8601 fallback.
      '2026-07-19T08:00:00Z': utc(2026, 7, 19, 8),
      '2026-07-19T08:00:00-05:00': utc(2026, 7, 19, 13),
    };
    cases.forEach((raw, want) {
      test(raw, () => expect(PodcastService.pubDateMs(raw), want));
    });

    test('offset crossing midnight lands on the next UTC day', () {
      expect(PodcastService.pubDateMs('Sat, 19 Jul 2026 22:00:00 -0500'),
          utc(2026, 7, 20, 3));
    });

    test('unparseable or empty → 0', () {
      expect(PodcastService.pubDateMs(null), 0);
      expect(PodcastService.pubDateMs(''), 0);
      expect(PodcastService.pubDateMs('yesterday'), 0);
      expect(PodcastService.pubDateMs('31 Feb 2026 08:00:00 GMT'), 0);
      expect(PodcastService.pubDateMs('19 Foo 2026 08:00:00 GMT'), 0);
    });

    test('sorts newest-first across mixed zones', () {
      final raws = [
        'Sat, 19 Jul 2026 08:00:00 EST', // 13:00Z
        'Sat, 19 Jul 2026 14:00:00 +0000', // 14:00Z
        'Sat, 19 Jul 2026 05:00 PDT', // 12:00Z
      ];
      final sorted = [...raws]..sort((a, b) =>
          PodcastService.pubDateMs(b).compareTo(PodcastService.pubDateMs(a)));
      expect(sorted, [raws[1], raws[0], raws[2]]);
    });
  });

  group('formatPubDate', () {
    test('compact date from the same parser', () {
      expect(PodcastService.formatPubDate('Sat, 19 Jul 2026 08:00:00 +0000'),
          '19 Jul 2026');
      expect(PodcastService.formatPubDate('Wed, 01 Jul 2026 08:00 PDT'),
          '1 Jul 2026');
      expect(PodcastService.formatPubDate('5 July 26'), '5 Jul 2026');
      expect(PodcastService.formatPubDate('2026-07-19T08:00:00Z'),
          '19 Jul 2026');
    });

    test('keeps the publisher-local calendar date', () {
      expect(PodcastService.formatPubDate('Sat, 19 Jul 2026 22:00:00 -0500'),
          '19 Jul 2026');
      expect(PodcastService.formatPubDate('2026-07-19T22:00:00-05:00'),
          '19 Jul 2026');
    });

    test('empty and unparseable', () {
      expect(PodcastService.formatPubDate(null), '');
      expect(PodcastService.formatPubDate(''), '');
      expect(PodcastService.formatPubDate('last week'), 'last week');
    });
  });
}
