import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/durationstate.dart';
import 'package:harmonymusic/services/lyrics_text_size.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final isLyricsLoading = false.obs;
  @override
  final lyricsMode = 1.obs; // plain lyrics
  @override
  RxMap<String, dynamic> lyrics =
      <String, dynamic>{'synced': '', 'plainLyrics': 'Hello'}.obs;
  @override
  final lyricUi = UINetease();
  @override
  final progressBarStatus = ProgressBarState(
          buffered: Duration.zero, current: Duration.zero, total: Duration.zero)
      .obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('the setting', () {
    setUp(() async {
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    });
    tearDown(() async {
      await LyricsTextSize.set(LyricsTextSize.standard);
      await Hive.box('AppPrefs').close();
    });

    test('is Default until chosen, then kept', () async {
      expect(LyricsTextSize.selected.value, LyricsTextSize.standard);
      await LyricsTextSize.set(LyricsTextSize.large);
      expect(LyricsTextSize.selected.value, LyricsTextSize.large);
      expect(Hive.box('AppPrefs').get(LyricsTextSize.key), 'large');
    });
  });

  test('sizes go on top of the phone font size', () {
    const scaler = ScaledTextScaler(TextScaler.linear(1.5), 1.2);
    expect(scaler.scale(10), closeTo(18, 1e-9));
    expect(const ScaledTextScaler(TextScaler.noScaling, 0.85).scale(20),
        closeTo(17, 1e-9));
    expect(scaler, const ScaledTextScaler(TextScaler.linear(1.5), 1.2));
  });

  test('text drawn without a Text widget gets the scaled size', () {
    expect(
        scaledTextStyle(
                const TextStyle(fontSize: 22), const TextScaler.linear(2))
            .fontSize,
        44);
    expect(
        scaledTextStyle(const TextStyle(), const TextScaler.linear(2)).fontSize,
        isNull);
  });

  testWidgets("synced lyrics' lines follow the phone and lyrics sizes",
      (tester) async {
    late RiffLyricUI ui;
    late double title;
    late double body;
    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: MediaQuery(
        data: const MediaQueryData(
            textScaler: ScaledTextScaler(TextScaler.linear(1.5), 1.2)),
        child: Builder(builder: (context) {
          final text = Theme.of(context).textTheme;
          title = text.titleLarge!.fontSize!;
          body = text.bodyMedium!.fontSize!;
          ui = RiffLyricUI.of(context, UINetease());
          return const SizedBox();
        }),
      ),
    ));
    expect(ui.getPlayingMainTextStyle().fontSize, closeTo(title * 1.8, 1e-9));
    expect(ui.getOtherMainTextStyle().fontSize, closeTo(title * 1.8, 1e-9));
    expect(ui.getPlayingExtTextStyle().fontSize, closeTo(body * 1.8, 1e-9));
    expect(ui.getOtherExtTextStyle().fontSize, closeTo(body * 1.8, 1e-9));
  });

  testWidgets('lyrics take the size chosen in Settings', (tester) async {
    Get.put<PlayerController>(_FakePlayer());
    addTearDown(Get.reset);
    addTearDown(() => LyricsTextSize.selected.value = LyricsTextSize.standard);

    await tester.pumpWidget(MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: LyricsWidget(padding: EdgeInsets.zero)),
    ));
    double lyricsSize(double fontSize) =>
        MediaQuery.textScalerOf(tester.element(find.byType(SelectableText)))
            .scale(fontSize);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(lyricsSize(10), closeTo(10, 1e-9));

    LyricsTextSize.selected.value = LyricsTextSize.largest;
    await tester.pump();
    expect(lyricsSize(10), closeTo(14.5, 1e-9));
  });
}
