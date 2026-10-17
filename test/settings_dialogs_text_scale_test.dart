import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final discoverContentType = "QP".obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Settings' dialogs with Android's larger font sizes: they used to have
/// fixed heights the text spilled out of (an overflow fails the test).
void main() {
  tearDown(Get.reset);

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final dialog in {
      'Discover content': () => const DiscoverContentSelectorDialog(),
      'Discovery settings': () => const DiscoverySettingsDialog(),
    }.entries) {
      testWidgets('${dialog.key} fits with the text at ${scale}x',
          (tester) async {
        Get.put<SettingsScreenController>(_FakeSettings());
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(GetMaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Scaffold(body: Center(child: dialog.value())),
        ));
        // Its last action can be reached.
        final last =
            find.text(dialog.key == 'Discover content' ? 'cancel' : 'confirm');
        await tester.scrollUntilVisible(last, 50,
            scrollable: find.byType(Scrollable).first);
        expect(last.hitTestable(), findsOneWidget);
      });
    }
  }
}
