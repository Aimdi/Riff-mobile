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

  static bool _isPodcast(MediaItem item) =>
      item.extras?['isPodcast'] == true || item.id.startsWith('podcast_');

  static bool get _dynamicTheme =>
      Get.isRegistered<SettingsScreenController>() &&
      Get.find<SettingsScreenController>().themeModetype.value ==
          ThemeType.dynamic;

  static Future<void> _compute(MediaItem item) async {
    if (!_pending.add(item.id)) return;
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
    } catch (e) {
      printERROR('Podcast tint failed: $e');
    } finally {
      _pending.remove(item.id);
    }
  }

  static ImageProvider? _provider(MediaItem item) {
    final art = item.artUri?.toString() ?? '';
    if (art.startsWith('file://')) return FileImage(File(art.substring(7)));
    if (art.startsWith('/')) return FileImage(File(art));
    if (art.isEmpty) return null;
    return CachedNetworkImageProvider(Thumbnail(art).medium);
  }
}
