import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/stats_service.dart';
import 'package:harmonymusic/ui/screens/Stats/stats_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:hive/hive.dart';

class _FakeDiscovery extends GetxService implements DiscoveryService {
  _FakeDiscovery(this.repo);

  @override
  final DiscoveryRepository repo;

  @override
  Map<String, dynamic> debugSnapshot() => {'artists': const []};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [id] started [times] times, [daysAgo] days back (plays are kept in the
/// order they happened, so append the oldest first).
Future<void> _started(DiscoveryRepository repo, String id,
    {required int daysAgo,
    int times = 1,
    String? artist,
    DiscoveryEventKind kind = DiscoveryEventKind.playStarted}) async {
  for (var i = 0; i < times; i++) {
    await repo.appendEvent(DiscoveryEvent(
      videoId: id,
      artistKey: 'artist',
      ts: DateTime.now()
          .subtract(Duration(days: daysAgo, minutes: times - i))
          .millisecondsSinceEpoch,
      source: DiscoverySource.search,
      event: kind,
      title: 'Song $id',
      artist: artist ?? 'Artist $id',
    ));
  }
}

void main() {
  late Directory tmp;
  late DiscoveryRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('riff_stats_ranges_');
    Hive.init(tmp.path);
    repo = DiscoveryRepository();
    await repo.open();
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('what you played lately, as Stats counts plays', () async {
    await _started(repo, 'old0000000a', daysAgo: 60, times: 9);
    await _started(repo, 'band000000a', daysAgo: 10, times: 2, artist: 'Band');
    await _started(repo, 'band000000b', daysAgo: 5, artist: 'Band');
    await _started(repo, 'solo000000a', daysAgo: 3, times: 2, artist: 'Solo');
    // Ends, skips and long-form don't count.
    await _started(repo, 'band000000a',
        daysAgo: 2, kind: DiscoveryEventKind.playEnded);
    await _started(repo, 'solo000000a',
        daysAgo: 2, kind: DiscoveryEventKind.skip);
    await _started(repo, 'podcast_1', daysAgo: 1, times: 5);

    final weeks = repo.playRowsSince(
        DateTime.now().subtract(Duration(days: StatsRange.fourWeeks.days!)));
    expect(weeks.keys,
        unorderedEquals(['band000000a', 'band000000b', 'solo000000a']));
    expect(weeks['band000000a'],
        {'title': 'Song band000000a', 'artist': 'Band', 'plays': 2});

    expect(rankTopSongs(weeks).map((s) => s['id']).take(2),
        unorderedEquals(['band000000a', 'solo000000a']));
    expect(rankTopArtists(weeks), [
      {'artist': 'Band', 'plays': 3},
      {'artist': 'Solo', 'plays': 2},
    ]);

    final months = repo.playRowsSince(
        DateTime.now().subtract(Duration(days: StatsRange.sixMonths.days!)));
    expect(rankTopSongs(months).first['id'], 'old0000000a');
  });

  testWidgets('Stats: the top songs and artists of the range you pick',
      (tester) async {
    await tester.runAsync(() async {
      await Hive.openBox('SongStats');
      await Hive.openBox('DailyStats');
      // All time, an old favourite leads.
      await Hive.box('SongStats').put('old0000000a',
          {'title': 'Old favourite', 'artist': 'Old Band', 'plays': 50});
      await Hive.box('SongStats').put('new0000000a',
          {'title': 'Song new0000000a', 'artist': 'New Band', 'plays': 3});
      await _started(repo, 'new0000000a',
          daysAgo: 2, times: 3, artist: 'New Band');
    });
    Get.put<DiscoveryService>(_FakeDiscovery(repo));
    // Tall enough for every row to be built.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const StatsScreen(),
    ));
    expect(find.text('Old favourite'), findsOneWidget);
    expect(find.text('Old Band'), findsWidgets);

    // `.tr` gives the key in tests.
    await tester.tap(find.text('statsRange4Weeks'));
    await tester.pump();
    expect(find.text('Old favourite'), findsNothing);
    expect(find.text('Song new0000000a'), findsOneWidget);
    expect(find.text('Old Band'), findsNothing);

    await tester.tap(find.text('statsRangeAllTime'));
    await tester.pump();
    expect(find.text('Old favourite'), findsOneWidget);

    // The new range's rows fade in in place of the last's; the rest of
    // the page stays put.
    double opacity(Finder f) => tester
        .widget<Opacity>(
            find.ancestor(of: f, matching: find.byType(Opacity)).first)
        .opacity;
    await tester.pump(RiffDurations.content * 0.5);
    expect(opacity(find.text('Old favourite')), inExclusiveRange(0, 1));
    expect(
        find.ancestor(
            of: find.text('statsRange4Weeks'), matching: find.byType(Opacity)),
        findsNothing);
    // Past the fade (not settled: the covers pulse while they load).
    await tester.pump(RiffDurations.content);
    expect(opacity(find.text('Old favourite')), 1);
  });
}
