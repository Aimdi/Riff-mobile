import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();

  final queued = <String>[];
  final nexts = <String>[];

  @override
  Future<bool> enqueueSong(MediaItem mediaItem) async {
    queued.add(mediaItem.id);
    return true;
  }

  @override
  Future<bool> playNext(MediaItem song) async {
    nexts.add(song.id);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;
  const song = MediaItem(id: 'song1', title: 'Song A', artist: 'Artist');

  setUp(() {
    player = _FakePlayer();
    Get.put<PlayerController>(player);
    Get.put<SettingsScreenController>(_FakeSettings());
  });
  tearDown(Get.reset);

  Future<void> pumpRow(WidgetTester tester, {Playlist? playlist}) =>
      tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: Scaffold(
          body: Semantics(
            container: true,
            child: SongListTile(
              song: song,
              playlist: playlist,
              thumbReplacementWithIndex: true,
              index: 1,
            ),
          ),
        ),
      ));

  testWidgets('the swipe actions are TalkBack actions on the row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester);
    expect(
      tester.getSemantics(find.byType(SongListTile)),
      containsSemantics(customActions: const [
        CustomSemanticsAction(label: 'addToQueue'),
        CustomSemanticsAction(label: 'playNext'),
        CustomSemanticsAction(label: 'addToPlaylist'),
      ]),
    );

    final row = find.semantics.byPredicate((n) =>
        n.getSemanticsData().customSemanticsActionIds?.isNotEmpty ?? false);
    tester.semantics.performAction(row, SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'addToQueue')));
    tester.semantics.performAction(row, SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'playNext')));
    await tester.pumpAndSettle();
    expect(player.queued, ['song1']);
    expect(player.nexts, ['song1']);
    semantics.dispose();
  });

  testWidgets('in a playlist the row can also be removed', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRow(tester,
        playlist: Playlist(
            title: 'Mine',
            playlistId: 'mine',
            thumbnailUrl: '',
            isCloudPlaylist: false));
    expect(
      tester.getSemantics(find.byType(SongListTile)),
      containsSemantics(customActions: const [
        CustomSemanticsAction(label: 'addToQueue'),
        CustomSemanticsAction(label: 'playNext'),
        CustomSemanticsAction(label: 'addToPlaylist'),
        CustomSemanticsAction(label: 'removeFromPlaylist'),
      ]),
    );
    semantics.dispose();
  });
}
