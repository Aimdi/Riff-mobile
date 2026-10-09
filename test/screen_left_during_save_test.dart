import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/ban_service.dart';
import 'package:harmonymusic/ui/screens/Plugins/spotify_bridge_screen.dart';
import 'package:harmonymusic/ui/screens/Settings/blacklist_screen.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

class _FakeTheme extends GetxController implements ThemeController {
  @override
  final accentColor = const Color(0xFF1DB954).obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Lets real I/O (Hive writes) finish; what it completes in the test's
/// fake-async zone only runs on pump.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

/// Leaves the screen while its awaited write is still pending, then lets
/// the write finish: nothing may touch the disposed State.
Future<void> _leaveAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

/// Closes Hive inside the test, for the same reason.
Future<void> _closeHive(WidgetTester tester) async {
  final closing = Hive.close();
  await _settle(tester);
  await tester.runAsync(() => closing);
}

void main() {
  late Directory tmp;

  setUp(() async {
    Get.reset();
    Get.put<ThemeController>(_FakeTheme());
    tmp = await Directory.systemTemp.createTemp('left_during_save');
    Hive.init(p.join(tmp.path, 'hive'));
    await Hive.openBox('AppPrefs');
  });
  tearDown(() async {
    Get.reset();
    await Hive.deleteFromDisk();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('Spotify: leaving right after saving the client id',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SpotifyBridgeScreen()));
    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.tap(find.byIcon(Icons.check));
    await _leaveAndSettle(tester);
    expect(Hive.box('AppPrefs').get('spotifyClientId'), 'abc123');
    await _closeHive(tester);
  });

  testWidgets('Never play: leaving right after removing an entry',
      (tester) async {
    await tester.runAsync(() async {
      await Hive.openBox('BannedSongs');
      await Hive.openBox('BannedArtists');
      await Hive.openBox('BannedCollections');
      await BanService.banArtist('Some Artist');
    });
    await tester.pumpWidget(const MaterialApp(home: BlacklistScreen()));
    expect(find.text('Some Artist'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded));
    await _leaveAndSettle(tester);
    expect(BanService.allArtists, isEmpty);
    await _closeHive(tester);
  });
}
