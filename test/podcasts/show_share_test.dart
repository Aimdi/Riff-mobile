import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_show_view.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

const _boxes = ['AppPrefs', 'PodcastProgress', 'PodcastPlayed', 'PodcastQueue'];
const _share = MethodChannel('dev.fluttercommunity.plus/share');

void main() {
  late List<MethodCall> shared;

  setUp(() async {
    for (final name in _boxes) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
    Get.put(PodcastQueueController());
    shared = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_share, (call) async {
      shared.add(call);
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_share, null);
    Get.reset();
    for (final name in _boxes) {
      await Hive.box(name).close();
    }
  });

  Future<void> pumpShow(WidgetTester tester, String showKey) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: PodcastShowView(
        title: 'The Show',
        author: 'Host',
        artUrl: '',
        description: '',
        episodes: const [
          MediaItem(
              id: 'podcast_1', title: 'Episode', extras: {'isPodcast': true}),
        ],
        loading: false,
        subscribed: true,
        onToggleSubscribe: () {},
        onPlay: (_) {},
        playbackKey: showKey,
      ),
    ));
  }

  testWidgets("a show's ⋮ shares its name and feed", (tester) async {
    await pumpShow(tester, 'https://feeds.example.com/show.xml');
    await tester.tap(find.byTooltip('moreOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shareShow'));
    await tester.pumpAndSettle();
    expect(shared.single.method, 'share');
    expect((shared.single.arguments as Map)['text'],
        'The Show\nhttps://feeds.example.com/show.xml');
  });

  testWidgets('a YouTube show shares its YouTube Music page', (tester) async {
    await pumpShow(tester, 'yt:PLabc');
    await tester.tap(find.byTooltip('moreOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('shareShow'));
    await tester.pumpAndSettle();
    expect((shared.single.arguments as Map)['text'],
        'The Show\nhttps://music.youtube.com/playlist?list=PLabc');
  });
}
