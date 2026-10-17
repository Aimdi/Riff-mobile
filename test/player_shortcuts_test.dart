import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/player_shortcuts.dart';

class _FakePlayer extends GetxController implements PlayerController {
  final calls = <String>[];

  @override
  final volume = 50.obs;

  @override
  void playPause() => calls.add('playPause');

  @override
  Future<bool> next() async {
    calls.add('next');
    return true;
  }

  @override
  Future<bool> prev({bool restart = true}) async {
    calls.add('previous');
    return true;
  }

  @override
  void seekBy(Duration offset) => calls.add('seek ${offset.inSeconds}');

  @override
  Future<void> setVolume(int value) async {
    calls.add('volume $value');
    volume.value = value;
  }

  @override
  Future<void> toggleShuffleMode() async => calls.add('shuffle');

  @override
  Future<void> cycleRepeatMode() async => calls.add('repeat');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key,
    {LogicalKeyboardKey? holding}) async {
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await tester.sendKeyEvent(key);
  if (holding != null) await tester.sendKeyUpEvent(holding);
}

void main() {
  late _FakePlayer player;
  setUp(() {
    player = _FakePlayer();
    Get.put<PlayerController>(player);
  });
  tearDown(Get.reset);

  /// The app's shape: shortcuts above the navigator, focus on a screen.
  Widget host(Widget body) => GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        builder: (context, child) => PlayerShortcuts(child: child!),
        home: Scaffold(body: body),
      );

  const ctrl = LogicalKeyboardKey.controlLeft;
  const shift = LogicalKeyboardKey.shiftLeft;

  testWidgets('Spotify-style keys drive the player from any screen',
      (tester) async {
    await tester.pumpWidget(
        host(const Focus(autofocus: true, child: SizedBox.expand())));
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.space);
    await _press(tester, LogicalKeyboardKey.arrowRight, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.arrowLeft, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.arrowRight, holding: shift);
    await _press(tester, LogicalKeyboardKey.arrowLeft, holding: shift);
    await _press(tester, LogicalKeyboardKey.arrowUp, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.arrowDown, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.keyS, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.keyR, holding: ctrl);
    // Plain arrows stay with focus traversal.
    await _press(tester, LogicalKeyboardKey.arrowRight);

    expect(player.calls, [
      'playPause',
      'next',
      'previous',
      'seek 10',
      'seek -10',
      'volume 60',
      'volume 50',
      'shuffle',
      'repeat',
    ]);
  });

  testWidgets('held down, only seeking and volume go on', (tester) async {
    await tester.pumpWidget(
        host(const Focus(autofocus: true, child: SizedBox.expand())));
    await tester.pump();

    await tester.sendKeyDownEvent(ctrl);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(ctrl);

    expect(player.calls, ['volume 60', 'volume 70', 'next']);
  });

  testWidgets('typing keeps its keys', (tester) async {
    final text = TextEditingController(text: 'hello world');
    addTearDown(text.dispose);
    await tester.pumpWidget(host(TextField(controller: text, autofocus: true)));
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.space);
    await _press(tester, LogicalKeyboardKey.arrowLeft, holding: ctrl);
    await _press(tester, LogicalKeyboardKey.keyS, holding: ctrl);
    expect(player.calls, isEmpty);
  });

  testWidgets('Ctrl+/ lists the shortcuts', (tester) async {
    await tester.pumpWidget(
        host(const Focus(autofocus: true, child: SizedBox.expand())));
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.slash, holding: ctrl);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsDialog), findsOneWidget);
    expect(find.text('Ctrl + →'), findsOneWidget);
    expect(find.text('Shift + ←'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(player.calls, isEmpty);
  });

  test('keys read as people know them', () {
    expect(
        describeShortcut(const SingleActivator(LogicalKeyboardKey.keyS,
            control: true, shift: true)),
        'Ctrl + Shift + S');
    expect(
        describeShortcut(
            const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true)),
        '⌘ + ↓');
  });
}
