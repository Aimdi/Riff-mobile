import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:palette_generator/palette_generator.dart';

import '/models/thumbnail.dart';
import '/services/podcast_inbox_cache.dart';
import '/ui/theme/riff_tokens.dart';
import '/utils/helper.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';

/// The podcast player's tint colour, taken from the episode's artwork.
/// Podcasts only, and only for the player: the app theme (and so every
/// music screen) is left alone. With the dynamic theme on, the theme
/// already follows the artwork and this stays out of the way.
///
/// The page itself stays black: the tint only shows as a top gradient of
/// at most [RiffPalette.playerTintOpacity] (CLAUDE.md rule 4), see
/// [backdrop].
class PodcastPlayerTint {
  PodcastPlayerTint._();

  /// Top-to-bottom gradient over the black [page]: [tint] at 20% at the
  /// top, fading into the page by 60% of the height (the music player's
  /// album-art tint shape).
  static LinearGradient backdrop(Color tint, Color page) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
              tint.withOpacity(RiffPalette.playerTintOpacity), page),
          page,
        ],
        stops: const [0, 0.6],
      );

  static const prefKey = 'podcastTintPlayer';

  /// Episode id → tint.
  static final colors = <String, Color>{}.obs;
  static final _pending = <String>{};

  /// Episodes whose artwork gives no tint: nothing to wait for. Reactive.
  static final _none = <String>{}.obs;

  /// The tint last shown, held while the next episode's is worked out.
  static Color? _lastShown;

  static bool get enabled {
    if (!Hive.isBoxOpen('AppPrefs')) return true;
    return Hive.box('AppPrefs').get(prefKey) != false;
  }

  static final enabledRx = true.obs;

  static Future<void> setEnabled(bool on) async {
    if (Hive.isBoxOpen('AppPrefs')) await Hive.box('AppPrefs').put(prefKey, on);
    enabledRx.value = on;
  }

  /// The tint for [item], or null (not a podcast, turned off, not ready,
  /// or the dynamic theme already does it). Reactive inside an Obx.
  static Color? of(MediaItem? item) {
    enabledRx.value;
    if (item == null || !_isPodcast(item) || !enabled) return null;
    if (_dynamicTheme) return null;
    final c = colors[item.id];
    if (c == null) _compute(item);
    return c;
  }

  /// What the player shows for [item]: its tint once ready; while it's
  /// worked out, the one shown before (so the page eases from one
  /// episode's colour to the next instead of flashing the cover look in
  /// between); null when [item] gets no tint. Reactive inside an Obx.
  static Color? shown(MediaItem? item) {
    final c = of(item);
    if (c != null) return _lastShown = c;
    if (item == null || !_isPodcast(item) || !enabled || _dynamicTheme) {
      return null;
    }
    return _none.contains(item.id) ? null : _lastShown;
  }

  static bool _isPodcast(MediaItem item) =>
      item.extras?['isPodcast'] == true || item.id.startsWith('podcast_');

  static bool get _dynamicTheme =>
      Get.isRegistered<SettingsScreenController>() &&
      Get.find<SettingsScreenController>().themeModetype.value ==
          ThemeType.dynamic;

  static Future<void> _compute(MediaItem item) async {
    if (_none.contains(item.id) || !_pending.add(item.id)) return;
    var found = false;
    try {
      final ImageProvider? provider = _provider(item);
      if (provider == null) return;
      final g = await PaletteGenerator.fromImageProvider(
          ResizeImage(provider, width: 64, height: 64));
      final base = g.dominantColor?.color ??
          g.darkMutedColor?.color ??
          g.vibrantColor?.color;
      if (base == null) return;
      // Keep a handful; the player only ever needs the current one.
      if (colors.length > 24) colors.remove(colors.keys.first);
      colors[item.id] = podcastPlayerTint(base);
      found = true;
    } catch (e) {
      printERROR('Podcast tint failed: $e');
    } finally {
      _pending.remove(item.id);
      // Not straight away: this can run inside a build (via [of]).
      if (!found) Future.microtask(() => _markNone(item.id));
    }
  }

  static void _markNone(String id) {
    if (_none.contains(id)) return;
    if (_none.length > 24) _none.remove(_none.first);
    _none.add(id);
  }

  static ImageProvider? _provider(MediaItem item) {
    final art = item.artUri?.toString() ?? '';
    if (art.startsWith('file://')) return FileImage(File(art.substring(7)));
    if (art.startsWith('/')) return FileImage(File(art));
    if (art.isEmpty) return null;
    return CachedNetworkImageProvider(Thumbnail(art).medium);
  }
}
