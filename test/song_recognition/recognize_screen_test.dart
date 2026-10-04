import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/song_recognition/shazam_client.dart';
import 'package:harmonymusic/services/song_recognition/song_recognizer.dart';
import 'package:harmonymusic/ui/screens/Recognize/recognize_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

/// No mic, no network: the screen just shows whatever state it's given.
class _FakeRecognizer extends SongRecognizer {
  _FakeRecognizer(this.initial);
  final RecognitionState initial;
  int starts = 0;

  @override
  Future<void> start() async {
    starts++;
    state.value = initial;
  }

  @override
  Future<void> stop() async {}
}

Future<_FakeRecognizer> _pump(WidgetTester tester, RecognitionState s,
    {RecognizedSong? song, List<RecognizedSong> history = const []}) async {
  Get.reset();
  final fake = Get.put<SongRecognizer>(_FakeRecognizer(s), permanent: true)
      as _FakeRecognizer;
  fake.result.value = song;
  fake.history.assignAll(history);
  await tester.pumpWidget(GetMaterialApp(
    theme: RiffTheme.dark(const Color(0xFF1DB954)),
    home: const RecognizeScreen(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return fake;
}

void main() {
  tearDown(Get.reset);

  const song = RecognizedSong(
      title: 'Monkeys Spinning Monkeys',
      artist: 'Kevin MacLeod',
      album: 'Comedy',
      released: '2014');

  testWidgets('starts listening on open and shows the match', (tester) async {
    final fake = await _pump(tester, RecognitionState.matched,
        song: song, history: [song]);
    expect(fake.starts, 1);
    expect(find.text('Monkeys Spinning Monkeys'), findsWidgets);
    expect(find.text('Comedy · 2014'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // Recent finds list below the result.
    await tester.scrollUntilVisible(find.text('RECOGNIZERECENT'), 300);
    expect(find.text('RECOGNIZERECENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no microphone permission offers the settings', (tester) async {
    await _pump(tester, RecognitionState.noPermission);
    expect(find.text('recognizeNoMic'), findsOneWidget);
    expect(find.text('recognizeOpenSettings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
