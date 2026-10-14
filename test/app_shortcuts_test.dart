import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/app_shortcuts.dart';

void main() {
  test('each shortcut opens from its own link', () {
    expect('${AppShortcut.search.uri}', 'riff://shortcut/search');
    for (final shortcut in AppShortcut.values) {
      expect(AppShortcut.fromUri(shortcut.uri), shortcut);
    }
  });

  test('other links are not shortcuts', () {
    expect(AppShortcut.fromUri(Uri.parse('riff://shortcut/nope')), isNull);
    expect(AppShortcut.fromUri(Uri.parse('riff://shortcut')), isNull);
    expect(AppShortcut.fromUri(Uri.parse('riff://other/search')), isNull);
    expect(
        AppShortcut.fromUri(Uri.parse('https://music.youtube.com/watch?v=abc')),
        isNull);
  });

  test('"Play … on Riff" from the Assistant comes as a voice link', () {
    expect(
        voiceSearchQuery(Uri.parse('riff://voice?q=daft%20punk')), 'daft punk');
    expect(voiceSearchQuery(Uri.parse('riff://voice?q=')), '');
    expect(voiceSearchQuery(Uri.parse('riff://voice')), '');
    expect(voiceSearchQuery(AppShortcut.search.uri), isNull);
    expect(voiceSearchQuery(Uri.parse('https://music.youtube.com/watch?v=a')),
        isNull);
    // Not a shortcut either.
    expect(AppShortcut.fromUri(Uri.parse('riff://voice?q=x')), isNull);
  });

  test("Android hands the Assistant's requests over as voice links", () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.media.action.MEDIA_PLAY_FROM_SEARCH'));
    final activity = File(
            'android/app/src/main/kotlin/com/anandnet/harmonymusic/MainActivity.kt')
        .readAsStringSync();
    expect(
        activity, contains('MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH'));
    expect(activity, contains('.scheme("riff")'));
    expect(activity, contains('.authority("voice")'));
    expect(activity, contains('appendQueryParameter("q"'));
  });

  test('labels are translated strings', () {
    final en = jsonDecode(File('localization/en.json').readAsStringSync())
        as Map<String, dynamic>;
    for (final shortcut in AppShortcut.values) {
      expect(en[shortcut.labelKey], isA<String>(), reason: shortcut.labelKey);
    }
  });

  test('Android has an icon for every shortcut', () {
    final activity = File(
            'android/app/src/main/kotlin/com/anandnet/harmonymusic/MainActivity.kt')
        .readAsStringSync();
    const res = 'android/app/src/main/res';
    for (final shortcut in AppShortcut.values) {
      final icon = 'ic_shortcut_${shortcut.id}';
      expect(activity, contains('"${shortcut.id}" to R.drawable.$icon'));
      // Android 7.1, and the adaptive icon (with its glyph) from 8.0.
      expect(File('$res/drawable/$icon.xml').existsSync(), isTrue);
      expect(File('$res/drawable-anydpi-v26/$icon.xml').existsSync(), isTrue);
      expect(File('$res/drawable/${icon}_fg.xml').existsSync(), isTrue);
    }
  });
}
