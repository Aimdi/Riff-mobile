import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_cover_tile.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_subs_screen.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/palettes/podcast_folders.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// The lines of [source] where an IconButton has no tooltip: TalkBack reads
/// such a button as a bare "Button", and a long press shows nothing.
List<int> iconButtonsWithoutTooltip(String source) {
  final lines = <int>[];
  for (final m in RegExp(r'\bIconButton(\.filled|\.filledTonal|\.outlined)?\(')
      .allMatches(source)) {
    var depth = 1;
    var i = m.end;
    while (i < source.length && depth > 0) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') depth--;
      i++;
    }
    if (!source.substring(m.end, i).contains('tooltip:')) {
      lines.add('\n'.allMatches(source.substring(0, m.start)).length + 1);
    }
  }
  return lines;
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final themeModetype = ThemeType.dark.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTheme extends GetxController implements ThemeController {
  @override
  final accentColor = ThemeController.riffAccents['Green']!.obs;

  @override
  void changeAccentColor(Color color) => accentColor.value = color;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(GetMaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: Center(child: child)),
    ));

void main() {
  tearDown(Get.reset);

  test('the scan finds the IconButtons without a tooltip', () {
    expect(iconButtonsWithoutTooltip('''
IconButton(icon: Icon(Icons.close), onPressed: f(x)),
IconButton(tooltip: 'close'.tr, icon: Icon(Icons.close)),
IconButton.filled(
  icon: Icon(Icons.play_arrow),
),
style: IconButton.styleFrom(padding: EdgeInsets.zero),
'''), [1, 3]);
  });

  test('every IconButton in Riff says what it does', () {
    final missing = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    var scanned = 0;
    for (final f in files) {
      final source = f.readAsStringSync();
      scanned += RegExp(r'\bIconButton\(').allMatches(source).length;
      for (final line in iconButtonsWithoutTooltip(source)) {
        missing.add('${f.path}:$line');
      }
    }
    expect(scanned, greaterThan(100), reason: 'the scan reads the app');
    expect(missing, isEmpty);
  });

  test('every colour has its name in English', () {
    final en = Languages().keys['en']!;
    expect(PodcastFolderColors.names,
        hasLength(PodcastFolderColors.swatches.length));
    for (final key in [
      ...PodcastFolderColors.names,
      for (final accent in ThemeController.riffAccents.keys) 'color$accent',
      'showPassword',
      'hidePassword',
      'syncPipedPlaylists',
      'accent',
    ]) {
      expect(en[key], isNotNull, reason: key);
    }
  });

  testWidgets("a show's play button is a button of its own, named Play",
      (tester) async {
    final handle = tester.ensureSemantics();
    var played = 0;
    var opened = 0;
    await _pump(
        tester,
        SizedBox(
          width: 160,
          height: 240,
          child: PodcastCoverTile(
            title: 'Show A',
            cover: const SizedBox.expand(),
            onTap: () => opened++,
            onPlay: () => played++,
          ),
        ));
    // `.tr` gives the key in tests.
    final play = find.bySemanticsLabel('play');
    expect(play, findsOneWidget);
    expect(tester.getSemantics(play),
        containsSemantics(label: 'play', isButton: true, hasTapAction: true));
    tester.semantics.tap(find.semantics.byLabel('play'));
    await tester.pump();
    expect(played, 1);
    expect(opened, 0);
    handle.dispose();
  });

  testWidgets("a folder's colours say their names, and which is picked",
      (tester) async {
    final handle = tester.ensureSemantics();
    var picked = -1;
    await _pump(
        tester,
        PodcastFolderColorPicker(
            selected: 2, onChanged: (index) => picked = index));
    expect(tester.getSemantics(find.bySemanticsLabel('colorPurple')),
        containsSemantics(isButton: true, isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('colorGreen')),
        containsSemantics(isButton: true, isSelected: false));
    tester.semantics.tap(find.semantics.byLabel('colorRed'));
    expect(picked, 3);
    handle.dispose();
  });

  testWidgets('the accent colours say their names, and which is picked',
      (tester) async {
    final handle = tester.ensureSemantics();
    Get.put<SettingsScreenController>(_FakeSettings());
    final theme = Get.put<ThemeController>(_FakeTheme()) as _FakeTheme;
    await _pump(tester, const ThemeSelectorDialog());
    expect(find.text('accent'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('colorGreen')),
        containsSemantics(isButton: true, isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('colorBlue')),
        containsSemantics(isButton: true, isSelected: false));

    tester.semantics.tap(find.semantics.byLabel('colorBlue'));
    await tester.pump();
    expect(theme.accentColor.value, ThemeController.riffAccents['Blue']);
    expect(tester.getSemantics(find.bySemanticsLabel('colorBlue')),
        containsSemantics(isSelected: true));

    // It fits its content, Cancel too, with the text twice as large.
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('cancel'), 50,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('cancel').hitTestable(), findsOneWidget);
    handle.dispose();
  });
}
