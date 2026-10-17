import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/discovery/discovery_math.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/discovery/taste_model.dart';
import 'package:harmonymusic/services/not_interested.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/not_interested_action.dart';
import 'package:hive/hive.dart';

MediaItem _song(String id) =>
    MediaItem(id: id, title: 'Song $id', artist: 'Artist $id');

/// Skips and takes songs out of Up Next, as asked.
class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  var skips = 0;
  final removed = <String>[];
  final putBack = <String>[];

  @override
  Future<bool> next() async {
    skips++;
    return true;
  }

  @override
  Future<VoidCallback?> removeFromQueueUndoable(MediaItem song) async {
    removed.add(song.id);
    return () => putBack.add(song.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiscovery extends GetxService implements DiscoveryService {
  final told = <String>[];

  @override
  Future<void> onNotInterested(MediaItem song, {bool undo = false}) async =>
      told.add('${undo ? 'undo ' : ''}${song.id}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await Hive.openBox(NotInterested.box, bytes: Uint8List(0));
  });
  tearDown(() async {
    Get.reset();
    await Hive.close();
  });

  test("radio and Up next leave out the songs you're not interested in",
      () async {
    await NotInterested.add(_song('b'));
    final songs = [_song('a'), _song('b'), _song('c')];
    expect(NotInterested.filter(songs).map((s) => s.id), ['a', 'c']);
    // The song asked for stays (its own radio starts with it).
    expect(NotInterested.filter(songs, keepId: 'b'), hasLength(3));
    final maps = [
      {'videoId': 'a'},
      {'videoId': 'b'},
    ];
    expect(NotInterested.filter(maps), [
      {'videoId': 'a'}
    ]);
    expect(NotInterested.hasTrack({'videoId': 'b'}), isTrue);

    await NotInterested.remove('b');
    expect(NotInterested.filter(songs), hasLength(3));
    await Hive.close();
    expect(NotInterested.filter(songs), hasLength(3), reason: 'not open');
  });

  test('what Riff and YouTube Music picked for you', () {
    for (final source in [
      DiscoverySource.radio,
      DiscoverySource.similar,
      DiscoverySource.smartShuffle,
      DiscoverySource.dailyMix,
      DiscoverySource.freshFinds,
      DiscoverySource.discover,
      DiscoverySource.related,
    ]) {
      expect(source.isPickedForYou, isTrue, reason: source.name);
    }
    for (final source in [
      DiscoverySource.userClick,
      DiscoverySource.search,
      DiscoverySource.playlist,
      DiscoverySource.album,
      DiscoverySource.home,
      DiscoverySource.queue,
      DiscoverySource.unknown,
    ]) {
      expect(source.isPickedForYou, isFalse, reason: source.name);
    }
  });

  test('its artist comes up a little less; Undo takes it back', () async {
    final tmp = await Directory.systemTemp.createTemp('riff_not_interested_');
    try {
      Hive.init(tmp.path);
      final repo = DiscoveryRepository();
      await repo.open();
      final taste = TasteModel(repo);
      final key = normalizeArtistKey('Band');
      await repo.bumpAffinity(key, 3);

      await taste.logDismiss('a', 'Band', 'Song');
      expect(repo.affinityOf(key), closeTo(3 + AffinityWeights.dismiss, 0.01));
      expect(repo.recentEvents().single.event, DiscoveryEventKind.dismiss);

      await taste.logDismiss('a', 'Band', 'Song', undo: true);
      expect(repo.affinityOf(key), closeTo(3, 0.01));
    } finally {
      await Hive.close();
      await tmp.delete(recursive: true);
    }
  });

  testWidgets(
      'Not interested: the playing song is skipped, one to come leaves Up '
      'Next; Undo puts it back', (tester) async {
    final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    final discovery =
        Get.put<DiscoveryService>(_FakeDiscovery()) as _FakeDiscovery;
    player.currentSong.value = _song('playing');
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    final context = tester.element(find.byType(SizedBox));

    final undoPlaying =
        await markNotInterested(_song('playing'), context: context);
    await tester.pump();
    expect(player.skips, 1);
    expect(player.removed, isEmpty);
    expect(NotInterested.has('playing'), isTrue);
    expect(discovery.told, ['playing']);
    expect(find.text('notInterestedDone'), findsOneWidget);

    await markNotInterested(_song('next'), context: context);
    // Its snackbar in place of the first one.
    await tester.pumpAndSettle();
    expect(player.skips, 1);
    expect(player.removed, ['next']);
    expect(find.text('undo'), findsOneWidget);

    // The snackbar's Undo: back in Up Next, and wanted again.
    await tester.tap(find.text('undo'));
    await tester.pump();
    expect(player.putBack, ['next']);
    expect(NotInterested.has('next'), isFalse);
    expect(discovery.told, ['playing', 'next', 'undo next']);

    undoPlaying();
    await tester.pump();
    expect(NotInterested.has('playing'), isFalse);
    await tester.pumpAndSettle();
  });
}
