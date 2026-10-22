import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the fonts the app ships, so text and icons render as glyphs
/// rather than the test font's boxes:
///
/// * every family in the test asset bundle's FontManifest.json: Inter
///   (pubspec, assets/fonts), MaterialIcons (uses-material-design) and the
///   ionicons package's Ionicons;
/// * Roboto, Material's own fallback family, and MaterialIcons again if
///   the bundle lacks it, from Flutter's cached material_fonts.
Future<void> loadShotFonts() async {
  final loaded = <String>{};
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
    loaded.add(family);
  }

  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> fromFiles(String family, bool Function(String name) take) async {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => take(f.uri.pathSegments.last))
        .toList();
    if (files.isEmpty) return;
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  await fromFiles(
      'Roboto', (n) => n.startsWith('Roboto-') && n.endsWith('.ttf'));
  if (!loaded.contains('MaterialIcons')) {
    await fromFiles('MaterialIcons', (n) => n == 'MaterialIcons-Regular.otf');
  }
}
