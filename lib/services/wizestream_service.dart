import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';

/// Hands YouTube podcasts (and videos) to WizeStream, the NewPipe-based
/// YouTube app, when it is installed. WizeStream's RouterActivity opens
/// `youtube.com/watch`, `/playlist` and `/channel` links, so a plain VIEW
/// intent aimed at its package is all it needs.
class WizeStream {
  WizeStream._();

  /// Release, debug and nightly builds (see WizeStream's ProjectConfig.kt).
  static const packages = [
    'org.wisso.newpipematerial',
    'org.wisso.newpipematerial.nightly',
    'org.wisso.newpipematerial.debug',
  ];

  static const _channel = MethodChannel('riff/apps');

  /// Installed WizeStream package, or null. Filled by [refresh].
  static final installedPackage = RxnString();

  static bool get isInstalled => installedPackage.value != null;

  /// Looks up which WizeStream build (if any) is installed.
  static Future<String?> refresh() async {
    try {
      final pkg = await _channel
          .invokeMethod<String>('installedPackage', {'packages': packages});
      installedPackage.value = pkg;
    } catch (_) {
      installedPackage.value = null;
    }
    return installedPackage.value;
  }

  /// Opens [url] in WizeStream. False when it isn't installed or refused.
  static Future<bool> open(String url) async {
    final pkg = installedPackage.value ?? await refresh();
    if (pkg == null) return false;
    try {
      return await _channel
              .invokeMethod<bool>('openUrl', {'url': url, 'package': pkg}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static final _videoId = RegExp(r'^[\w-]{11}$');

  /// `youtube.com/watch` link for a YouTube episode or video; null for RSS
  /// episodes, Audiobookshelf items and local files.
  static String? watchUrlFor(MediaItem item) {
    final id = item.id;
    if (id.startsWith('podcast_') || id.startsWith('abs_')) return null;
    if (!_videoId.hasMatch(id)) return null;
    return 'https://www.youtube.com/watch?v=$id';
  }

  /// Link for a followed YouTube show: its playlist (`MPSP` + `PL…`) or
  /// channel (`UC…`); null for anything else.
  static String? showUrlFor(Playlist show) {
    var id = show.playlistId.trim();
    if (id.startsWith('MPSP')) id = id.substring(4);
    if (RegExp(r'^UC[\w-]{20,}$').hasMatch(id)) {
      return 'https://www.youtube.com/channel/$id';
    }
    if (RegExp(r'^(PL|OL|UU|FL|RD)[\w-]{10,}$').hasMatch(id)) {
      return 'https://www.youtube.com/playlist?list=$id';
    }
    return null;
  }
}
