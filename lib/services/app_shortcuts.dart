/// Long-press shortcuts on Riff's app icon (Android 7.1+), as Spotify and
/// YouTube Music have: Search, Favorites and Downloads. Each opens the app
/// with a riff://shortcut/… link, which app_links hands to [filterLinks]
/// like a shared one.
library;

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/utils/helper.dart';

enum AppShortcut {
  search('search', 'search'),
  liked('liked', 'favorites'),
  downloads('downloads', 'downloads');

  const AppShortcut(this.id, this.labelKey);

  /// Also names its icon in MainActivity.
  final String id;
  final String labelKey;

  static const scheme = 'riff';
  static const host = 'shortcut';

  Uri get uri => Uri(scheme: scheme, host: host, path: '/$id');

  /// The shortcut a link opens, or null for any other link.
  static AppShortcut? fromUri(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    for (final shortcut in values) {
      if (shortcut.id == segments.first) return shortcut;
    }
    return null;
  }
}

/// "Play … on Riff" from the Assistant: MainActivity hands its request
/// (MEDIA_PLAY_FROM_SEARCH) over as riff://voice?q=…, which app_links
/// passes on like a shortcut. The request a link carries ('' for "play
/// music on Riff"), or null for any other link.
String? voiceSearchQuery(Uri uri) {
  if (uri.scheme != AppShortcut.scheme || uri.host != 'voice') return null;
  return uri.queryParameters['q']?.trim() ?? '';
}

class AppShortcuts {
  AppShortcuts._();

  static const _channel = MethodChannel('riff/apps');

  /// Puts the shortcuts on the app icon, labelled in the app's language
  /// (so again after the language changes).
  static Future<void> publish() async {
    if (!GetPlatform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setShortcuts', {
        'shortcuts': [
          for (final s in AppShortcut.values)
            {'id': s.id, 'label': s.labelKey.tr, 'uri': '${s.uri}'},
        ],
      });
    } catch (e) {
      printERROR('App shortcuts: $e');
    }
  }
}
