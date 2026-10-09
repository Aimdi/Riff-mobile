import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:hive/hive.dart';

class _BrightnessObserver with WidgetsBindingObserver {
  int changes = 0;
  @override
  void didChangePlatformBrightness() => changes++;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('theme_brightness');
    Hive.init(tmp.path);
    await Hive.openBox('AppPrefs');
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  testWidgets('the theme controller keeps the framework told of brightness',
      (tester) async {
    final observer = _BrightnessObserver();
    WidgetsBinding.instance.addObserver(observer);
    addTearDown(() => WidgetsBinding.instance.removeObserver(observer));
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final controller = ThemeController();
    await tester.pumpWidget(Builder(
        builder: (context) => Text(
            '${MediaQuery.platformBrightnessOf(context)}',
            textDirection: TextDirection.ltr)));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    expect(controller.systemBrightness, Brightness.light);
    // Was 0: the controller replaced the binding's handler, so observers
    // and MediaQuery never heard about the change.
    expect(observer.changes, 1);
    expect(find.text('${Brightness.light}'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(controller.systemBrightness, Brightness.dark);
    expect(observer.changes, 2);
    expect(find.text('${Brightness.dark}'), findsOneWidget);
  });
}
