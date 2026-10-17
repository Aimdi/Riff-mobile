import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_metrics.dart';
import 'package:harmonymusic/ui/screens/Home/home_shelves.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

class _FakePlayer extends GetxController implements PlayerController {
  List<MediaItem>? played;
  PlaylingFrom? from;

  @override
  final currentSong = Rxn<MediaItem>();

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played = mediaItems;
    from = playfrom;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(Get.reset);

  testWidgets('a Daily Mix played from Home plays as the playlist it opens as',
      (tester) async {
    final player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    final mix = GeneratedMix(
      id: 'daily1',
      title: 'Daily Mix 1',
      reason: '',
      kind: 'daily_mix',
      tracks: [
        {'videoId': 'aaaaaaaaaaa', 'title': 'A'},
        {'videoId': 'bbbbbbbbbbb', 'title': 'B'},
      ],
      generatedTs: 0,
    );
    await tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(
        body: HomeShelfItem(
            value: mix,
            kind: HomeShelfKind.mixes,
            metrics: const HomeMetrics(400)),
      ),
    ));

    // Its menu's Play (`.tr` gives the key in tests).
    await tester.longPress(find.text('Daily Mix 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('play'));
    await tester.pump();

    expect(player.played?.map((m) => m.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    // "Playing from" names the mix and opens it as its playlist (it said
    // Random selection), so one left out of your taste stays out.
    final from = player.from!;
    expect(from.type, PlaylingFromType.PLAYLIST);
    expect(from.nameString, 'Daily Mix 1');
    expect(from.id, 'RIFF_daily1');
    expect((from.item as Playlist).isCloudPlaylist, isFalse);
  });
}
