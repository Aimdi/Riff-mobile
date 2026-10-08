import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/discovery/discovery_tag.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/ui/player/components/queue_panel.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id', artist: 'A');

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  final isCurrentSongFav = false.obs;

  List<MediaItem>? playedList;
  int? playedIndex;

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    playedList = mediaItems;
    playedIndex = index;
    currentSong.value = mediaItems[index];
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiscovery extends GetxService implements DiscoveryService {
  final seeds = <String>[];

  @override
  Future<List<MediaItem>> similarSongs(MediaItem seed,
      {int limit = 25, bool unheardOnly = false}) async {
    seeds.add(seed.id);
    return [for (var i = 0; i < 3; i++) _song('${seed.id}-sim$i')];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;
  late _FakeDiscovery discovery;

  setUp(() {
    Get.reset();
    player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    Get.put<SettingsScreenController>(_FakeSettings());
    discovery = Get.put<DiscoveryService>(_FakeDiscovery()) as _FakeDiscovery;
  });
  tearDown(Get.reset);

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: SimilarSongsPanelList(topPadding: 0)),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lists songs similar to the one playing', (tester) async {
    player.currentSong.value = _song('a');
    await pumpList(tester);

    expect(discovery.seeds, ['a']);
    expect(find.text('Song a-sim0'), findsOneWidget);
    expect(find.text('Song a-sim2'), findsOneWidget);
  });

  testWidgets('a picked song plays with the list as queue, list stays',
      (tester) async {
    player.currentSong.value = _song('a');
    await pumpList(tester);

    await tester.tap(find.text('Song a-sim1'));
    await tester.pump();
    await tester.pump();

    expect(player.playedIndex, 1);
    expect(player.playedList!.map((s) => s.id), ['a-sim0', 'a-sim1', 'a-sim2']);
    expect(player.playedList![1].extras?[kDiscoverySourceExtra],
        DiscoverySource.similar.wireName);
    // No reload for the song just picked.
    expect(discovery.seeds, ['a']);
    expect(find.text('Song a-sim0'), findsOneWidget);
  });

  testWidgets('a new song from elsewhere reloads the list', (tester) async {
    player.currentSong.value = _song('a');
    await pumpList(tester);

    player.currentSong.value = _song('b');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(discovery.seeds, ['a', 'b']);
    expect(find.text('Song b-sim0'), findsOneWidget);
  });
}
