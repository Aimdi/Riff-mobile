import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/upcoming_queue.dart';

void main() {
  group('upcomingAfterIndex', () {
    test('returns songs after the current index', () {
      expect(upcomingAfterIndex(['a', 'b', 'c', 'd'], 1), ['c', 'd']);
    });

    test('is empty when current is last or queue is empty', () {
      expect(upcomingAfterIndex(['a', 'b'], 1), isEmpty);
      expect(upcomingAfterIndex(['a'], 0), isEmpty);
      expect(upcomingAfterIndex(<String>[], 0), isEmpty);
    });

    test('is empty for an out-of-range index', () {
      expect(upcomingAfterIndex(['a', 'b'], -1), isEmpty);
      expect(upcomingAfterIndex(['a', 'b'], 4), isEmpty);
    });
  });

  group('upcomingPreviewLabel', () {
    test('shows the next title and remaining count', () {
      expect(upcomingPreviewLabel('Next Song', 1), 'Next Song');
      expect(upcomingPreviewLabel('Next Song', 4), 'Next Song · 3 more');
      expect(upcomingPreviewLabel('Next Song', 0), '');
    });
  });
}
