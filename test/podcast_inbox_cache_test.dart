import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';

void main() {
  group('mapWithConcurrency', () {
    test('keeps input order and never exceeds the limit', () async {
      var inFlight = 0;
      var peak = 0;
      final items = List.generate(20, (i) => i);
      final out = await mapWithConcurrency(items, 6, (int i) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        // Later items finish sooner, so order must come from the index.
        await Future.delayed(Duration(milliseconds: 20 - i));
        inFlight--;
        return i * 2;
      });
      expect(out, [for (final i in items) i * 2]);
      expect(peak, 6);
    });

    test('handles empty input and fewer items than workers', () async {
      expect(await mapWithConcurrency(<int>[], 6, (int i) async => i), []);
      expect(await mapWithConcurrency([1, 2], 6, (int i) async => i + 1),
          [2, 3]);
    });
  });

  group('inbox cache', () {
    final eps = [const MediaItem(id: 'a', title: 'a')];

    test('fresh while young and built from the same subscriptions', () {
      final c = LibraryPodcastsController();
      expect(c.freshInbox('k'), isNull);
      c.storeInbox(eps, 'k');
      expect(c.freshInbox('k'), eps);
      expect(c.freshInbox('other'), isNull);
    });

    test('stale after the max age', () {
      final c = LibraryPodcastsController();
      c.storeInbox(eps, 'k');
      c.inboxFetchedAt = DateTime.now()
          .subtract(LibraryPodcastsController.inboxMaxAge)
          .subtract(const Duration(seconds: 1));
      expect(c.freshInbox('k'), isNull);
    });
  });
}
