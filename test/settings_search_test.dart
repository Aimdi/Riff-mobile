import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Settings/components/custom_expansion_tile.dart';

void main() {
  test('ListTile matches on title or subtitle text', () {
    const tile = ListTile(
        title: Text('Lyrics source'),
        subtitle: Text('Where synced lyrics are fetched from'));
    expect(settingsChildMatches(tile, 'lyrics'), isTrue);
    expect(settingsChildMatches(tile, 'synced'), isTrue);
    expect(settingsChildMatches(tile, 'theme'), isFalse);
  });

  test('SettingsSearchable carries the text of Obx-built tiles', () {
    const w = SettingsSearchable(
        title: 'Data saver',
        subtitle: 'Use low streaming quality',
        child: SizedBox.shrink());
    expect(settingsChildMatches(w, 'data'), isTrue);
    expect(settingsChildMatches(w, 'streaming'), isTrue);
    expect(settingsChildMatches(w, 'shorts'), isFalse);
  });

  testWidgets('the search field shows the search still in effect',
      (tester) async {
    Widget field(String query) => MaterialApp(
          home: Material(
            child: SettingsSearchField(
                query: query,
                builder: (c) => TextField(controller: c, onChanged: (_) {})),
          ),
        );
    // Back on the Settings tab with "lyrics" still filtering the list.
    await tester.pumpWidget(field('lyrics'));
    expect(find.text('lyrics'), findsOneWidget);

    // Typing keeps working on the same controller.
    await tester.enterText(find.byType(TextField), 'theme');
    await tester.pump();
    expect(find.text('theme'), findsOneWidget);

    // A fresh screen with no search starts empty.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(field(''));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
  });

  test('unknown widgets defer to the section (null)', () {
    expect(settingsChildMatches(const SizedBox.shrink(), 'x'), isNull);
    expect(
        settingsChildMatches(
            ListTile(title: Builder(builder: (_) => const Text('a'))), 'a'),
        isNull);
  });
}
