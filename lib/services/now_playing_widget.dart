/// The home screen widget (Android), like Spotify's and YouTube Music's:
/// the song or episode playing, its art, and previous, play/pause and next.
/// The widget itself is native (NowPlayingWidget.kt); this tells it what to
/// show over "riff/widget" whenever that changes.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';

class NowPlayingWidget {
  NowPlayingWidget._();

  static const channel = MethodChannel('riff/widget');

  static AudioHandler? _handler;
  static Future<String?> Function(MediaItem item) _artPath = _cachedArt;
  static final _subs = <StreamSubscription<Object?>>[];
  static Worker? _themeWorker;
  static Timer? _soon;
  static int _sends = 0;
  static Map<String, Object?>? _sent;

  /// Keeps the widget showing what [handler] plays. [artPath] finds a local
  /// file for an item's art (by default audio_service's copy).
  static void start(AudioHandler handler,
      {Future<String?> Function(MediaItem item)? artPath}) {
    stop();
    _handler = handler;
    _artPath = artPath ?? _cachedArt;
    _subs
      ..add(handler.mediaItem.listen((_) => refresh()))
      ..add(handler.playbackState
          .map((state) => state.playing)
          .distinct()
          .listen((_) => refresh()));
    // The play button is in the accent.
    if (Get.isRegistered<ThemeController>()) {
      _themeWorker =
          ever(Get.find<ThemeController>().themedata, (_) => refresh());
    }
  }

  static void stop() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _themeWorker?.dispose();
    _themeWorker = null;
    _soon?.cancel();
    _soon = null;
    _handler = null;
    _sent = null;
  }

  /// Sends what's playing now (once for a burst of changes), e.g. after
  /// the app's language changed the buttons' labels.
  static void refresh() {
    if (_handler == null) return;
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 300), _send);
  }

  static Future<void> _send() async {
    final handler = _handler;
    if (handler == null) return;
    final send = ++_sends;
    final item = handler.mediaItem.value;
    String? art;
    if (item != null) {
      try {
        art = await _artPath(item).timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    // Something changed meanwhile: a newer send has it.
    if (send != _sends || handler != _handler) return;
    final scheme = Get.isRegistered<ThemeController>()
        ? Get.find<ThemeController>().themedata.value?.colorScheme
        : null;
    final args = nowPlayingWidgetArgs(
      item: item,
      artPath: art,
      playing: handler.playbackState.value.playing,
      accent: scheme?.primary ?? ThemeController.riffAccents['Green']!,
      onAccent: scheme?.onPrimary ?? RiffPalette.onAccent,
      labels: nowPlayingWidgetLabels(),
    );
    if (mapEquals(args, _sent)) return;
    try {
      await channel.invokeMethod<void>('update', args);
      _sent = args;
    } on MissingPluginException {
      // No activity has set the channel up yet: the next change sends.
    } on PlatformException {
      // The widget keeps what it had.
    }
  }

  static String? _artUrl;
  static String? _artFile;

  static Future<String?> _cachedArt(MediaItem item) async {
    final uri = item.artUri;
    final local = nowPlayingLocalArt(uri);
    if (local != null) return local;
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    final url = uri.toString();
    if (url == _artUrl) return _artFile;
    final file = await AudioService.cacheManager
        .getSingleFile(url, headers: item.artHeaders ?? const {});
    _artUrl = url;
    _artFile = file.path;
    return file.path;
  }
}

/// The local file [artUri] points at, if it is one.
String? nowPlayingLocalArt(Uri? artUri) {
  if (artUri == null) return null;
  if (artUri.isScheme('file')) return artUri.toFilePath();
  if (!artUri.hasScheme && artUri.path.startsWith('/')) return artUri.path;
  return null;
}

/// The buttons' labels, in the app's language (for TalkBack).
Map<String, String> nowPlayingWidgetLabels() => {
      for (final key in const ['play', 'pause', 'next', 'previous'])
        key: key.tr,
    };

/// What the widget shows: [item]'s title and artist (none: nothing has
/// played yet), its art from [artPath], whether it's [playing], the play
/// button's colours and the buttons' [labels].
Map<String, Object?> nowPlayingWidgetArgs({
  required MediaItem? item,
  required String? artPath,
  required bool playing,
  required Color accent,
  required Color onAccent,
  required Map<String, String> labels,
}) {
  String? text(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  return {
    'title': text(item?.title),
    'artist': text(item?.artist) ?? text(item?.album),
    'art': item == null ? null : artPath,
    'playing': playing,
    'accent': accent.value,
    'onAccent': onAccent.value,
    ...labels,
  };
}
