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

  test('unknown widgets defer to the section (null)', () {
    expect(settingsChildMatches(const SizedBox.shrink(), 'x'), isNull);
    expect(
        settingsChildMatches(
            ListTile(title: Builder(builder: (_) => const Text('a'))), 'a'),
        isNull);
  });
}
