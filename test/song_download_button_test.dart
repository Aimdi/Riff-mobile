import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/song_download_btn.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloader extends GetxController implements Downloader {
  @override
  RxList<MediaItem> songQueue = <MediaItem>[].obs;
  @override
  MediaItem? currentSong;
  @override
  final songDownloadingProgress = 0.obs;
  @override
  final isJobRunning = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _song = MediaItem(id: 'a', title: 'Song A');

void main() {
  late _FakeDownloader downloader;

  setUp(() async {
    await Hive.openBox('SongDownloads', bytes: Uint8List(0));
    Get.put<PlayerController>(_FakePlayer());
    downloader = Get.put<Downloader>(_FakeDownloader()) as _FakeDownloader;
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('SongDownloads').close();
  });

  Finder pops() => find.descendant(
      of: find.byType(SongDownloadButton),
      matching: find.byType(ScaleTransition));

  testWidgets('its states crossfade, and the tick pops in when done',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home:
          const Scaffold(body: Center(child: SongDownloadButton(song_: _song))),
    ));
    expect(find.byTooltip('download'), findsOneWidget);
    final buttonSize = tester.getSize(find.byType(SongDownloadButton));

    // Queued: the arrow gives way to the spinner, and can't be tapped
    // again as it fades.
    downloader.songQueue.add(_song);
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 2);
    expect(find.byTooltip('download'), findsOneWidget);
    expect(
        tester
            .widget<IgnorePointer>(find
                .ancestor(
                    of: find.byTooltip('download'),
                    matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        isTrue);
    expect(pops(), findsNothing);
    // Then the button eases down to the spinner's size, never jumping.
    final widths = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      widths.add(tester.getSize(find.byType(SongDownloadButton)).width);
    }
    expect(find.byTooltip('download'), findsNothing);
    expect(widths.last, lessThan(buttonSize.width));
    expect(widths.where((w) => w < buttonSize.width && w > widths.last),
        isNotEmpty);

    // Downloading, then done.
    downloader
      ..currentSong = _song
      ..isJobRunning.value = true
      ..songDownloadingProgress.value = 40;
    await tester.pump();
    await tester.pump(RiffDurations.select);
    await tester.pump(RiffDurations.select);
    expect(find.text('40%'), findsOneWidget);

    downloader.songDownloadingProgress.value = 100;
    await tester.pump();
    await tester.pump(RiffDurations.select ~/ 4);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    expect(pops(), findsWidgets);
  });
}
