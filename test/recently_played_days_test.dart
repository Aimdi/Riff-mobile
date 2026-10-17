import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/recently_played_days.dart';
import 'package:hive/hive.dart';

void main() {
  final now = DateTime(2026, 10, 14, 9, 30);
  int at(int day, int hour) =>
      DateTime(2026, 10, day, hour).millisecondsSinceEpoch;

  test('Recently played keeps the song and when it was played', () {
    final entry =
        recentlyPlayedEntry(const MediaItem(id: 'a', title: 'A'), now);
    expect(entry['videoId'], 'a');
    expect(entry[recentlyPlayedAtKey], now.millisecondsSinceEpoch);
    // Songs kept before it noted the time have none.
    expect(
        recentlyPlayedTimes([
          entry,
          {'videoId': 'old', 'title': 'Old'},
          'not an entry',
        ]),
        {'a': now.millisecondsSinceEpoch});
  });

  test('a heading where each day begins: Today, Yesterday, then the date', () {
    expect(
        recentlyPlayedHeadings(
            [at(14, 9), at(14, 8), at(13, 22), at(10, 7), at(10, 6)], now),
        ['today', null, 'yesterday', '10 Oct 2026', null]);
  });

  test('songs from before the times were kept come last, under Earlier', () {
    expect(recentlyPlayedHeadings([at(14, 9), null, null], now),
        ['today', 'earlier', null]);
  });

  test('no song with a time, or another order: no headings, as before', () {
    expect(recentlyPlayedHeadings([null, null], now), [null, null]);
    // Sorted by name, say.
    expect(recentlyPlayedHeadings([at(13, 9), at(14, 9)], now), [null, null]);
    expect(recentlyPlayedHeadings([null, at(14, 9)], now), [null, null]);
    expect(recentlyPlayedHeadings([], now), isEmpty);
  });

  group('clear history', () {
    Map<String, dynamic> entry(String id) => {'videoId': id, 'title': id};
    List<Object?> ids() => [
          for (final e in Hive.box(recentlyPlayedBox).values)
            (e as Map)['videoId']
        ];

    setUp(() async {
      final box = await Hive.openBox(recentlyPlayedBox, bytes: Uint8List(0));
      await box.addAll([entry('a'), entry('b'), entry('c')]);
    });
    tearDown(() async {
      await Hive.box(recentlyPlayedBox).close();
    });

    test('empties it; Undo puts it back before what played since', () async {
      final held = await clearRecentlyPlayed();
      expect(ids(), isEmpty);
      // Played meanwhile: one new, one again.
      await Hive.box(recentlyPlayedBox).addAll([entry('d'), entry('b')]);
      await restoreRecentlyPlayed(held);
      expect(ids(), ['a', 'c', 'd', 'b']);
    });

    test('at most as many as it keeps, the newest', () async {
      final held = [
        for (var i = 0; i < recentlyPlayedMax; i++) entry('old$i'),
      ];
      await clearRecentlyPlayed();
      await Hive.box(recentlyPlayedBox).add(entry('new'));
      await restoreRecentlyPlayed(held);
      expect(ids(), hasLength(recentlyPlayedMax));
      expect(ids().first, 'old1');
      expect(ids().last, 'new');
    });
  });
}
