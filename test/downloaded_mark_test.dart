import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/downloaded_mark.dart';
import 'package:harmonymusic/ui/widgets/song_list_tile.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final isCurrentSongFav = false.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = true.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = MediaItem(id: 'a', title: 'Song A', artist: 'Artist');

Finder get _mark => find.byIcon(Icons.download_for_offline_rounded);

/// Changes the downloads box (real async) and lets its change events arrive
/// before the next frame.
Future<void> _downloads(
        WidgetTester tester, Future<void> Function(Box box) change) =>
    tester.runAsync(() async {
      await change(Hive.box('SongDownloads'));
      await Future<void>.delayed(Duration.zero);
    });

void main() {
  setUp(() async {
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    Get.put<PlayerController>(_FakePlayer());
    Get.put<SettingsScreenController>(_FakeSettings());
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('SongDownloads').close();
  });

  Future<void> pumpRow(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(
          body: SongListTile(
              song: _song, thumbReplacementWithIndex: true, index: 1),
        ),
      ));

  testWidgets('a downloaded song shows the mark before its artist',
      (tester) async {
    await _downloads(tester, (box) => box.put('a', {'videoId': 'a'}));
    final semantics = tester.ensureSemantics();
    await pumpRow(tester);
    expect(find.byType(DownloadedMark), findsOneWidget);
    expect(_mark, findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('downloaded')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('it comes when the download finishes and goes when deleted',
      (tester) async {
    await pumpRow(tester);
    expect(_mark, findsNothing);

    await _downloads(tester, (box) => box.put('a', {'videoId': 'a'}));
    await tester.pump();
    expect(_mark, findsOneWidget);

    // Another song's download changes nothing here.
    await _downloads(tester, (box) => box.put('b', {'videoId': 'b'}));
    await tester.pump();
    expect(_mark, findsOneWidget);

    await _downloads(tester, (box) => box.delete('a'));
    await tester.pump();
    // It fades out, then its room closes.
    await tester.pumpAndSettle();
    expect(_mark, findsNothing);
  });

  testWidgets('it fades in as the artist glides over to make room',
      (tester) async {
    await pumpRow(tester);
    final before = tester.getTopLeft(find.text('Artist')).dx;

    await _downloads(tester, (box) => box.put('a', {'videoId': 'a'}));
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    final fade = tester.widget<FadeTransition>(
        find.ancestor(of: _mark, matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    final mid = tester.getTopLeft(find.text('Artist')).dx;
    expect(mid, greaterThan(before));

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Artist')).dx, greaterThan(mid));
  });
}
