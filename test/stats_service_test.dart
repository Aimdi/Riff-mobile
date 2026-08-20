import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/stats_service.dart';

void main() {
  test('skip under 30 percent increments skips not seconds of full duration', () {
    final next = applyListenEnd(
      {'plays': 1, 'seconds': 0, 'skips': 0},
      listenedMs: 20 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.search,
      title: 'Song',
      artist: 'A',
    );
    expect(next['skips'], 1);
    expect(next['partials'], 0);
    expect(next['completes'], 0);
    expect(next['seconds'], 20);
    expect(next['lastSource'], 'search');
    expect(next['lastFraction'], closeTo(0.10, 0.001));
  });

  test('partial listen 40 percent is a partial not a skip', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 80 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.album,
    );
    expect(next['skips'], 0);
    expect(next['partials'], 1);
    expect(next['completes'], 0);
    expect(next['seconds'], 80);
  });

  test('full listen 90 percent is a complete', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 180 * 1000,
      totalMs: 200 * 1000,
      source: DiscoverySource.radio,
    );
    expect(next['completes'], 1);
    expect(next['skips'], 0);
    expect(next['lastSource'], 'radio');
  });

  test('unknown duration under 10s is a quick skip', () {
    final next = applyListenEnd(
      const {},
      listenedMs: 4000,
      totalMs: 0,
      source: DiscoverySource.home,
    );
    expect(next['skips'], 1);
    expect(next['seconds'], 4);
    expect(next['lastFraction'], isNull);
  });
}
