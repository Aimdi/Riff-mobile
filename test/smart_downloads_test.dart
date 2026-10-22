import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/smart_downloads.dart';
import 'package:harmonymusic/ui/screens/Settings/components/smart_downloads_setting.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _day = 24 * 3600 * 1000;
const _now = 1760000000000;

/// A song's listening, as SongStats keeps it.
Map<String, Object?> _heard(int plays,
        {int skips = 0, int daysAgo = 1, String kind = ''}) =>
    {
      'title': 'Song',
      'artist': 'Artist',
      'plays': plays,
      'skips': skips,
      'lastPlayed': _now - daysAgo * _day,
      if (kind.isNotEmpty) 'kind': kind,
    };

void main() {
  late Box prefs;
  late Box downloads;
  late Box stats;
  final queued = <String>[];
  final removed = <String>[];
  String? playing;
  var metered = false;
  var storageReady = true;
  var clock = _now;

  setUp(() async {
    prefs = await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    downloads = await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    stats = await Hive.openBox('SongStats', bytes: Uint8List(0));
    await Hive.openBox('LIBFAV', bytes: Uint8List(0));
    await Hive.openBox('LibraryPlaylists', bytes: Uint8List(0));
    await prefs.put(SmartDownloads.key, true);
    SmartDownloads.reload();
    queued.clear();
    removed.clear();
    playing = null;
    metered = false;
    storageReady = true;
    clock = _now;
    SmartDownloads.metered = () async => metered;
    SmartDownloads.storageReady = () async => storageReady;
    SmartDownloads.queue =
        (songs) async => queued.addAll(songs.map((s) => s.id));
    SmartDownloads.removeDownload = (id) async {
      removed.add(id);
      await downloads.delete(id);
    };
    SmartDownloads.playingId = () => playing;
    SmartDownloads.now = () => clock;
  });
  tearDown(() => Hive.close());

  /// What the downloader does with what's queued: downloads it.
  Future<void> downloadQueued() async {
    for (final id in queued) {
      await downloads.put(id, {'videoId': id, 'title': id, 'url': '/m/$id'});
    }
    queued.clear();
  }

  group('the songs it keeps', () {
    List<String> picks(Map<String, Object?> stats,
            {int count = 50, Set<String> leaveOut = const {}}) =>
        [
          for (final p in smartPicks(stats,
              count: count,
              nowMs: _now,
              leaveOut: leaveOut,
              banned: (id) => id == 'banned00001'))
            p['id'] as String,
        ];

    test('most heard through first, the latest played among equals', () {
      expect(
          picks({
            'aaaaaaaaaaa': _heard(3),
            'bbbbbbbbbbb': _heard(9, skips: 2),
            'ccccccccccc': _heard(3, daysAgo: 0),
          }),
          ['bbbbbbbbbbb', 'ccccccccccc', 'aaaaaaaaaaa']);
    });

    test('music you came back to lately, from YouTube', () {
      expect(
          picks({
            'once0000000': _heard(1),
            'skipped0000': _heard(5, skips: 4),
            'longago0000': _heard(20, daysAgo: 120),
            'podcast_123': _heard(9),
            'episode0000': _heard(9, kind: 'podcast'),
            'device_1234': _heard(9),
            'cloud_77': _heard(9),
            'banned00001': _heard(9),
            'gone0000000': _heard(9),
            'kept0000000': _heard(2),
          }, leaveOut: {
            'gone0000000'
          }),
          ['kept0000000']);
    });

    test('as many as asked for', () {
      final many = {
        for (var i = 0; i < 30; i++)
          'song${'$i'.padLeft(7, '0')}': _heard(2 + i),
      };
      expect(picks(many, count: 25), hasLength(25));
      expect(picks(many, count: 25).first, 'song0000029');
    });
  });

  test('downloads the ones not downloaded yet, once a day', () async {
    await stats.putAll({
      'aaaaaaaaaaa': _heard(5),
      'bbbbbbbbbbb': _heard(4),
      'ccccccccccc': _heard(3),
    });
    // Downloaded already, by you.
    await downloads.put('bbbbbbbbbbb', {'videoId': 'bbbbbbbbbbb'});

    expect(await SmartDownloads.run(), SmartDownloadsRun.started);
    expect(queued, ['aaaaaaaaaaa', 'ccccccccccc']);
    expect(SmartDownloads.started, 2);

    // Not again so soon…
    queued.clear();
    clock += 3600 * 1000;
    expect(await SmartDownloads.run(), SmartDownloadsRun.notDue);
    expect(queued, isEmpty);
    // …unless asked (Settings).
    expect(await SmartDownloads.run(force: true), SmartDownloadsRun.started);
    await downloadQueued();
    clock += _day;
    expect(await SmartDownloads.run(), SmartDownloadsRun.upToDate);
    expect(queued, isEmpty);
  });

  test('on mobile data it waits for Wi-Fi; off, it does nothing', () async {
    await stats.put('aaaaaaaaaaa', _heard(5));
    metered = true;
    expect(await SmartDownloads.run(), SmartDownloadsRun.waitingForWifi);
    expect(queued, isEmpty);

    metered = false;
    await SmartDownloads.set(false);
    expect(await SmartDownloads.run(force: true), SmartDownloadsRun.off);
    expect(queued, isEmpty);
    expect(prefs.get(SmartDownloads.key), isFalse);
  });

  test("a look of its own doesn't ask for the download folder", () async {
    await stats.put('aaaaaaaaaaa', _heard(5));
    storageReady = false;
    expect(await SmartDownloads.run(), SmartDownloadsRun.notDue);
    expect(queued, isEmpty);
    // Switched on in Settings: the download asks.
    expect(await SmartDownloads.run(force: true), SmartDownloadsRun.started);
  });

  test('nothing played often enough yet', () async {
    await stats.put('aaaaaaaaaaa', _heard(1));
    expect(await SmartDownloads.run(), SmartDownloadsRun.nothingYet);
  });

  test('one you delete stays deleted', () async {
    await stats.putAll({
      'aaaaaaaaaaa': _heard(5),
      'bbbbbbbbbbb': _heard(4),
    });
    await SmartDownloads.run();
    await downloadQueued();
    await SmartDownloads.run(force: true);
    expect(prefs.get(SmartDownloads.keptKey),
        unorderedEquals(['aaaaaaaaaaa', 'bbbbbbbbbbb']));

    // You delete one of them.
    await downloads.delete('aaaaaaaaaaa');
    expect(await SmartDownloads.run(force: true), SmartDownloadsRun.upToDate);
    expect(queued, isEmpty);
    expect(prefs.get(SmartDownloads.declinedKey), ['aaaaaaaaaaa']);
    expect(prefs.get(SmartDownloads.keptKey), ['bbbbbbbbbbb']);
  });

  test('ones you stopped playing make room, unless you keep them', () async {
    final songs = [
      'dropped0000',
      'liked000000',
      'mine0000000',
      'inamix00000',
      'playing0000',
    ];
    for (final id in songs) {
      await stats.put(id, _heard(5));
    }
    await SmartDownloads.run();
    await downloadQueued();
    await SmartDownloads.run(force: true);
    expect(prefs.get(SmartDownloads.keptKey), unorderedEquals(songs));

    // Liked, in your playlist, in one of Riff's mixes, playing now.
    await Hive.box('LIBFAV').put('liked000000', {'videoId': 'liked000000'});
    final mine = await Hive.openBox('PLmine', bytes: Uint8List(0));
    await mine.add({'videoId': 'mine0000000'});
    final mix = await Hive.openBox('RIFF_mix', bytes: Uint8List(0));
    await mix.add({'videoId': 'inamix00000'});
    await Hive.box('LibraryPlaylists').putAll({
      'PLmine': {
        'playlistId': 'PLmine',
        'isCloudPlaylist': false,
        'isPipedPlaylist': false,
      },
      'RIFF_mix': {
        'playlistId': 'RIFF_mix',
        'isCloudPlaylist': false,
        'isPipedPlaylist': false,
      },
    });
    playing = 'playing0000';

    // Heard last four months ago: no longer among them.
    for (final id in songs) {
      await stats.put(id, _heard(5, daysAgo: 120));
    }
    await stats.put('newfavorite', _heard(3));
    clock += _day;
    expect(await SmartDownloads.run(), SmartDownloadsRun.started);
    expect(removed, unorderedEquals(['dropped0000', 'inamix00000']));
    expect(queued, ['newfavorite']);
    expect(prefs.get(SmartDownloads.keptKey),
        unorderedEquals(['liked000000', 'mine0000000', 'playing0000']));
  });

  test('one you download yourself is yours: never removed', () async {
    await stats.put('yours000000', _heard(5));
    await SmartDownloads.run();
    await downloadQueued();
    await SmartDownloads.run(force: true);
    expect(prefs.get(SmartDownloads.keptKey), ['yours000000']);

    // You download it too (an album it's on): no longer Smart downloads'.
    await SmartDownloads.claim(['yours000000']);
    expect(prefs.get(SmartDownloads.keptKey), isEmpty);

    await stats.put('yours000000', _heard(5, daysAgo: 120));
    clock += _day;
    await SmartDownloads.run();
    expect(removed, isEmpty);
  });

  test('how many it keeps: 25, 50 or 100', () async {
    expect(SmartDownloads.count.value, SmartDownloads.defaultCount);
    await SmartDownloads.setCount(100);
    expect(prefs.get(SmartDownloads.countKey), 100);
    expect(SmartDownloads.count.value, 100);
    await SmartDownloads.setCount(7);
    expect(SmartDownloads.count.value, 100);
  });

  testWidgets('Settings: switched on, how many, and what it came to',
      (tester) async {
    await tester.runAsync(() => prefs.put(SmartDownloads.key, false));
    SmartDownloads.reload();
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: SmartDownloadsSetting()),
    ));
    expect(find.text('smartDownloads'), findsOneWidget);
    expect(find.text('smartDownloadsCount'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(prefs.get(SmartDownloads.key), isTrue);
    expect(find.text('smartDownloadsCount'), findsOneWidget);
    expect(find.text('${SmartDownloads.defaultCount}'), findsOneWidget);
    // Nothing played yet: it says so.
    expect(find.text('smartDownloadsNothingYet'), findsOneWidget);
  });
}
