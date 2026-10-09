import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_inbox_screen.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One followed YouTube Music show; the Inbox cache is always cold.
class _FakeLib extends GetxController implements LibraryPodcastsController {
  @override
  String inboxSubsKey = '';
  @override
  List<MediaItem>? inboxEpisodes;
  @override
  final libraryPodcasts = <Playlist>[
    Playlist(
        title: 'Show', playlistId: 'PLshow', thumbnailUrl: '', kind: 'podcast'),
  ].obs;
  final stored = <List<MediaItem>>[];
  @override
  List<MediaItem>? freshInbox(String subsKey) => null;
  @override
  void storeInbox(List<MediaItem> episodes, String subsKey) =>
      stored.add(episodes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Each feed fetch waits until the test completes it.
class _FakeMusic extends GetxService implements MusicServices {
  final pending = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> getPodcast(String playlistId,
      {int limit = 100}) {
    final c = Completer<Map<String, dynamic>>();
    pending.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _feed(String title) => {
      'tracks': [
        MediaItem(id: 'id_$title', title: title, extras: const {}),
      ],
    };

/// Bumps the Inbox's refresh nonce on demand.
class _Host extends StatefulWidget {
  const _Host({required this.nonce});
  final ValueNotifier<int> nonce;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: widget.nonce,
        builder: (_, n, __) => PodcastInboxScreen(refreshNonce: n),
      );
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('riff_inbox_race_');
    Hive.init(tmp.path);
    // PodcastInboxCache's box stays closed: its save is then a no-op (a
    // real disk write inside a widget test's fake clock never finishes).
    for (final b in [
      'PodcastSubs',
      'PodcastProgress',
      'PodcastPlayed',
      'PodcastQueue',
      'PodcastDownloads',
      PodcastBookmarkStore.box,
    ]) {
      await Hive.openBox(b);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  setUp(() {
    Get.reset();
    Get.put<PlayerController>(_FakePlayer());
    Get.put(PodcastQueueController());
  });
  tearDown(Get.reset);

  testWidgets('an older load finishing last does not replace a newer one',
      (tester) async {
    final lib = Get.put<LibraryPodcastsController>(_FakeLib()) as _FakeLib;
    final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
    final nonce = ValueNotifier(0);
    await tester.pumpWidget(GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: _Host(nonce: nonce)),
    ));
    // First load (no cache) is waiting on its feed; the refresh shortcut
    // starts a second one.
    expect(music.pending, hasLength(1));
    nonce.value++;
    await tester.pump();
    expect(music.pending, hasLength(2));

    // The newer load answers first, then the old one.
    music.pending[1].complete(_feed('Fresh episode'));
    await tester.pump();
    await tester.pump();
    music.pending[0].complete(_feed('Stale episode'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Fresh episode'), findsOneWidget);
    expect(find.text('Stale episode'), findsNothing);
    expect(lib.stored.map((l) => l.single.title), ['Fresh episode']);
  });

  testWidgets('unfollowing everything clears the list on refresh',
      (tester) async {
    final lib = Get.put<LibraryPodcastsController>(_FakeLib()) as _FakeLib;
    final music = Get.put<MusicServices>(_FakeMusic()) as _FakeMusic;
    final nonce = ValueNotifier(0);
    await tester.pumpWidget(GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: _Host(nonce: nonce)),
    ));
    music.pending.single.complete(_feed('Old show episode'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Old show episode'), findsOneWidget);

    lib.libraryPodcasts.clear();
    nonce.value++;
    await tester.pump();
    await tester.pump();
    expect(find.text('Old show episode'), findsNothing);
  });
}
