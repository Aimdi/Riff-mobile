import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/podcast_download_service.dart';
import 'package:harmonymusic/services/podcast_library.dart';
import 'package:harmonymusic/services/podcast_starred.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_screen.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_starred_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _feed = 'https://example.com/feed';

MediaItem _episode(int n, {String? notes}) => MediaItem(
      id: 'podcast_ep$n',
      title: 'Episode $n',
      artist: 'Show',
      duration: const Duration(minutes: 30),
      extras: {
        'isPodcast': true,
        'url': 'https://example.com/ep$n.mp3',
        'feedUrl': _feed,
        if (notes != null) 'description': notes,
      },
    );

class _FakePlayer extends GetxController implements PlayerController {
  final played = <String>[];

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played.add(mediaItems[index].id);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _boxes = [
  StarredEpisodes.box,
  'AppPrefs',
  'PodcastDownloads',
  'PodcastPlayed',
  'PodcastProgress',
  'PodcastShowLibrary',
  'PodcastQueue',
];

List<String> _ids() => [for (final e in StarredEpisodes.all) e.id];

void main() {
  late _FakePlayer player;

  setUp(() async {
    for (final name in _boxes) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
    Get.put(PodcastQueueController());
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
  });
  tearDown(() async {
    Get.reset();
    for (final name in _boxes) {
      await Hive.box(name).close();
    }
  });

  test('newest starred first, episodes only, show notes kept', () async {
    expect(
        await StarredEpisodes.star(_episode(1, notes: 'What it is about'),
            now: DateTime(2026, 10, 12)),
        isTrue);
    expect(await StarredEpisodes.star(_episode(2), now: DateTime(2026, 10, 13)),
        isTrue);
    expect(await StarredEpisodes.star(const MediaItem(id: 'song', title: 'S')),
        isFalse);
    expect(_ids(), ['podcast_ep2', 'podcast_ep1']);
    expect(StarredEpisodes.isStarred('podcast_ep1'), isTrue);
    expect(StarredEpisodes.isStarred('song'), isFalse);

    // Playable again, notes and all.
    final item = StarredEpisodes.entry('podcast_ep1')!.item!;
    expect(item.title, 'Episode 1');
    expect(item.extras?['url'], 'https://example.com/ep1.mp3');
    expect(item.extras?['description'], 'What it is about');

    final kept = StarredEpisodes.entry('podcast_ep2')!;
    await StarredEpisodes.unstar('podcast_ep2');
    expect(_ids(), ['podcast_ep1']);
    await StarredEpisodes.restore([kept]);
    expect(_ids(), ['podcast_ep2', 'podcast_ep1']);
  });

  test('a starred episode keeps its download when finished ones go', () async {
    final dir = await Directory.systemTemp.createTemp('riff_starred_');
    addTearDown(() => dir.delete(recursive: true));
    final finished = DateTime(2026, 10, 1).millisecondsSinceEpoch;
    for (final n in [1, 2]) {
      final file = File('${dir.path}/ep$n.mp3')..writeAsStringSync('audio');
      await Hive.box('PodcastDownloads').put('podcast_ep$n',
          {'path': file.path, 'title': 'Episode $n', 'feedUrl': _feed});
      await Hive.box('PodcastPlayed').put('podcast_ep$n', finished);
    }
    await Hive.box('AppPrefs')
        .put(PodcastLibrary.autoDeleteKey, AutoDeletePolicy.immediately.name);
    await StarredEpisodes.star(_episode(2));

    expect(await PodcastLibrary.sweepDownloads(now: DateTime(2026, 10, 13)), 1);
    expect(PodcastDownloadService.isDownloaded('podcast_ep1'), isFalse);
    expect(PodcastDownloadService.isDownloaded('podcast_ep2'), isTrue);
    expect(File('${dir.path}/ep2.mp3').existsSync(), isTrue);
  });

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: body),
    ));
  }

  testWidgets('star from the episode menu, unstar with Undo', (tester) async {
    await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddToQueueSheet(context, _episode(1)),
            child: const Text('episode'),
          ),
        ));
    await tester.tap(find.text('episode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('starEpisode'));
    await tester.pumpAndSettle();
    expect(_ids(), ['podcast_ep1']);
    expect(find.text('episodeStarred'), findsOneWidget);

    await tester.tap(find.text('episode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('unstarEpisode'));
    await tester.pumpAndSettle();
    expect(_ids(), isEmpty);
    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    expect(_ids(), ['podcast_ep1']);
  });

  testWidgets('nothing starred yet', (tester) async {
    await pump(tester, const PodcastStarredScreen());
    expect(find.text('noStarredEpisodes'), findsOneWidget);
  });

  testWidgets('the Starred tab: tap plays, swipe unstars with Undo',
      (tester) async {
    await tester.runAsync(() async {
      await StarredEpisodes.star(_episode(1), now: DateTime(2026, 10, 12));
      await StarredEpisodes.star(_episode(2), now: DateTime(2026, 10, 13));
    });
    await pump(tester, const PodcastStarredScreen());
    expect(find.text('Show · 30m'), findsNWidgets(2));

    await tester.tap(find.text('Episode 1'));
    await tester.pumpAndSettle();
    expect(player.played, ['podcast_ep1']);

    await tester.drag(find.text('Episode 2'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Episode 2'), findsNothing);
    expect(_ids(), ['podcast_ep1']);
    expect(find.text('episodeUnstarred'), findsOneWidget);

    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 2'), findsOneWidget);
    expect(_ids(), ['podcast_ep2', 'podcast_ep1']);
  });
}
