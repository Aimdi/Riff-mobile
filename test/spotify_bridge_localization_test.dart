import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/get_localization.dart';

/// GetX renders a missing key as the raw key string, so a typo in a `.tr` call
/// ships as literal "spotifySignIn" on the button instead of failing anywhere.
/// These tests make that failure loud.
void main() {
  late Map<String, String> en;
  late Map<String, dynamic> enJson;

  setUpAll(() {
    en = Languages().keys['en']!;
    enJson = jsonDecode(File('localization/en.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  /// Every `.tr` key referenced by the Spotify bridge UI.
  const spotifyKeys = <String>[
    'spotifyBridge',
    'spotifyBridgeDes',
    'spotifyBridgePluginDes',
    'spotifyClientId',
    'spotifyClientIdSaved',
    'spotifyNoClientId',
    'spotifyOpenDashboard',
    'spotifyRedirectUri',
    'spotifySignIn',
    'spotifySignOut',
    'spotifyConnected',
    'spotifyLoadingLibrary',
    'spotifyNoPlaylists',
    'spotifyYourPlaylists',
  ];

  /// Shared keys the new screens reuse from elsewhere in the app.
  const reusedKeys = <String>[
    'save',
    'close',
    'refresh',
    'import',
    'songs',
    'spotifyImportFetching',
    'spotifyImportResolving',
    'spotifyImportSaving',
    'spotifyImportNoMatches',
    'spotifyImportDone',
    'importedFromSpotify',
  ];

  test('every Spotify bridge key exists in the generated translations', () {
    final missing = spotifyKeys.where((k) => !en.containsKey(k)).toList();
    expect(missing, isEmpty,
        reason: 'these would render as their own key name in the UI');
  });

  test('reused keys the Spotify screens depend on still exist', () {
    final missing = reusedKeys.where((k) => !en.containsKey(k)).toList();
    expect(missing, isEmpty);
  });

  test('no Spotify key resolves to an empty string', () {
    for (final k in spotifyKeys) {
      expect(en[k]?.trim().isNotEmpty, isTrue, reason: '$k is blank');
    }
  });

  // The Dart file is generated from the JSON; if someone edits en.json and
  // forgets to re-run localization/generator.dart, the app ships the old text.
  test('generated translations are in sync with en.json', () {
    final drifted = spotifyKeys
        .where((k) => enJson[k] != null && enJson[k] != en[k])
        .toList();
    expect(drifted, isEmpty,
        reason: 'run: dart run localization/generator.dart');
  });
}
