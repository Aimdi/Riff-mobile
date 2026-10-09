import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/cloud_music_service.dart';
import 'package:harmonymusic/services/soul_sync_service.dart';
import 'package:harmonymusic/services/torrent_search_service.dart';
import 'package:harmonymusic/ui/screens/Cloud/cloud_screen.dart';
import 'package:harmonymusic/ui/screens/Plugins/soul_sync_screen.dart';
import 'package:harmonymusic/ui/screens/Plugins/torrent_search_screen.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class _FakeTheme extends GetxController implements ThemeController {
  @override
  final accentColor = const Color(0xFF1DB954).obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Each search waits until the test answers it.
class _FakeTorrents extends TorrentSearchFacade {
  final calls = <(String, int?)>[];
  final pending = <String, Completer<List<TorrentHit>>>{};
  int? nextCursor;

  @override
  Future<({List<TorrentHit> torrents, int? csvNext, String? error})> search(
    String query, {
    required Set<TorrentSourceId> sources,
    int? csvAfter,
  }) async {
    calls.add((query, csvAfter));
    final c = pending[query] = Completer<List<TorrentHit>>();
    final hits = await c.future;
    return (torrents: hits, csvNext: nextCursor, error: null);
  }

  void answer(String query, String name) => pending.remove(query)!.complete([
        TorrentHit(
          name: name,
          infoHash: 'h',
          magnet: 'magnet:?xt=urn:btih:h',
          sizeLabel: '1 MB',
          dateLabel: '—',
          seeders: 1,
          leechers: 0,
          downloads: 0,
          source: TorrentSourceId.torrentsCsv,
        )
      ]);
}

class _FakeSoulSync extends GetxController implements SoulSyncService {
  @override
  final isConnected = true.obs;
  @override
  final host = 'https://soulsync.test'.obs;
  @override
  final statusMessage = ''.obs;

  final pending = <String, Completer<List<SoulSyncTrack>>>{};

  @override
  Future<List<SoulSyncTrack>> searchTracks(String query, {int limit = 25}) =>
      (pending[query] = Completer<List<SoulSyncTrack>>()).future;

  void answer(String query, String name) => pending
      .remove(query)!
      .complete([SoulSyncTrack(id: name, name: name, artists: const [])]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCloud extends GetxService implements CloudMusicService {
  @override
  final isConnected = true.obs;
  @override
  final host = 'https://cloud.test'.obs;
  @override
  final username = 'me'.obs;
  @override
  final albums = <CloudAlbum>[].obs;
  @override
  final albumsHaveMore = false.obs;
  @override
  final playlists = <CloudPlaylist>[].obs;
  @override
  final songs = <CloudSong>[].obs;

  final pending = <String, Completer<CloudSearchResult>>{};

  @override
  Future<CloudSearchResult> search(String query) =>
      (pending[query] = Completer<CloudSearchResult>()).future;

  @override
  String coverUrl(String? coverArt, {int size = 400}) => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _submit(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

void main() {
  late Directory tmp;

  setUp(() async {
    Get.reset();
    Get.put<ThemeController>(_FakeTheme());
    tmp = await Directory.systemTemp.createTemp('search_race');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('AppPrefs');
  });
  tearDown(() async {
    Get.reset();
    await Hive.deleteFromDisk();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('torrents: a slower older search does not replace the newer',
      (tester) async {
    final torrents = _FakeTorrents()..nextCursor = 5;
    await tester
        .pumpWidget(MaterialApp(home: TorrentSearchScreen(facade: torrents)));

    await _submit(tester, 'old');
    await _submit(tester, 'new');
    torrents.answer('new', 'New hit');
    await tester.pump();
    torrents.answer('old', 'Old hit');
    await tester.pump();
    expect(find.text('New hit'), findsOneWidget);
    expect(find.text('Old hit'), findsNothing);

    // "Load more" continues the search that is shown, not the edited text.
    await tester.enterText(find.byType(TextField).first, 'edited');
    await tester.tap(find.text('loadMore'));
    await tester.pump();
    expect(torrents.calls.last, ('new', 5));
    torrents.answer('new', 'New hit 2');
    await tester.pump();
    expect(find.text('New hit 2'), findsOneWidget);
  });

  testWidgets('SoulSync: a slower older search does not replace the newer',
      (tester) async {
    final soulSync = Get.put<SoulSyncService>(_FakeSoulSync()) as _FakeSoulSync;
    await tester.pumpWidget(const MaterialApp(home: SoulSyncScreen()));

    await _submit(tester, 'old');
    await _submit(tester, 'new');
    soulSync.answer('new', 'New track');
    await tester.pump();
    soulSync.answer('old', 'Old track');
    await tester.pump();
    expect(find.text('New track'), findsOneWidget);
    expect(find.text('Old track'), findsNothing);
  });

  testWidgets('Cloud: results of a cleared search do not come back',
      (tester) async {
    final cloud = Get.put<CloudMusicService>(_FakeCloud()) as _FakeCloud;
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: CloudScreen())));

    await _submit(tester, 'song');
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    cloud.pending.remove('song')!.complete(
        CloudSearchResult(songs: [CloudSong(id: '1', title: 'Late result')]));
    await tester.pump();
    expect(find.text('Late result'), findsNothing);
    expect(find.text('cloudNoAlbums'), findsOneWidget);
  });
}
