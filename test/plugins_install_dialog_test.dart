import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/plugin_service.dart';
import 'package:harmonymusic/ui/screens/Plugins/plugins_screen.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:hive/hive.dart';

class _FakeTheme extends GetxController implements ThemeController {
  @override
  final accentColor = const Color(0xFF1DB954).obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// All four plugin tiles on screen.
Future<void> _pumpPlugins(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: PluginsScreen()));
}

void main() {
  setUp(() async {
    Get.reset();
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    Get.put<ThemeController>(_FakeTheme());
    Get.put(PluginService());
  });
  tearDown(() async {
    Get.reset();
    await Hive.box('AppPrefs').close();
  });

  testWidgets(
      'closing the Soulseek "installing" dialog with Back keeps '
      'the Plugins screen', (tester) async {
    await _pumpPlugins(tester);
    await tester.tap(find.text('downloadPlugin').last); // Soulseek is last
    await tester.pump();
    expect(find.text('soulseekInstalling'), findsOneWidget);

    await tester.binding.handlePopRoute(); // Android back
    await tester.pump();
    expect(find.text('soulseekInstalling'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(PluginsScreen), findsOneWidget);
    expect(Get.find<PluginService>().isInstalled(PluginIds.seeker), isTrue);
  });

  testWidgets('the dialog still closes by itself', (tester) async {
    await _pumpPlugins(tester);
    await tester.tap(find.text('downloadPlugin').last);
    await tester.pump();
    expect(find.text('soulseekInstalling'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('soulseekInstalling'), findsNothing);
    expect(find.byType(PluginsScreen), findsOneWidget);
  });
}
