import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:palette_generator/palette_generator.dart';

import '/models/thumbnail.dart';
import '/ui/theme/riff_tokens.dart';
import '/utils/helper.dart';
import '../../screens/Settings/settings_screen_controller.dart';

/// The music player's colours, taken from the cover: the page fills with
/// the cover's own colour under the full-bleed art, darkens towards the
/// bottom, and a second colour from the cover glows behind the transport.
@immutable
class CoverPalette {
  const CoverPalette({
    required this.fill,
    required this.deep,
    required this.glow,
  });

  /// Page colour right under the cover (where the art fades out).
  final Color fill;

  /// Page colour at the bottom edge.
  final Color deep;

  /// Soft light behind the transport.
  final Color glow;

  @override
  bool operator ==(Object other) =>
      other is CoverPalette &&
      other.fill == fill &&
      other.deep == deep &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(fill, deep, glow);
}

/// Turns the cover's [dominant] colour (and a [secondary] one for the glow)
/// into a [CoverPalette] that white text always reads on: the fill keeps
/// the cover's hue but is held dark enough for at least 6:1 contrast with
/// white, so a pale or yellow cover still gives a readable page.
CoverPalette coverPaletteFrom({required Color dominant, Color? secondary}) {
  final fill = _readableFill(dominant);
  final fillHsl = HSLColor.fromColor(fill);
  final deep = fillHsl
      .withLightness(fillHsl.lightness * CoverTone.deepLightness)
      .toColor();
  // Glow: the second colour when it differs enough from the fill to show,
  // else the fill's hue turned a little towards magenta.
  var glowHsl = secondary == null ? null : HSLColor.fromColor(secondary);
  if (glowHsl == null ||
      _hueDistance(glowHsl.hue, fillHsl.hue) < CoverTone.glowMinHueShift ||
      glowHsl.saturation < CoverTone.glowMinSaturation) {
    glowHsl = fillHsl.withHue((fillHsl.hue + CoverTone.glowHueShift) % 360);
  }
  final glow = glowHsl
      .withSaturation(glowHsl.saturation.clamp(
          CoverTone.glowMinSaturation, CoverTone.maxSaturation))
      .withLightness(CoverTone.glowLightness)
      .toColor();
  return CoverPalette(fill: fill, deep: deep, glow: glow);
}

Color _readableFill(Color c) {
  var hsl = HSLColor.fromColor(c);
  hsl = hsl.withSaturation(hsl.saturation.clamp(0, CoverTone.maxSaturation));
  hsl = hsl.withLightness(
      hsl.lightness.clamp(CoverTone.minLightness, CoverTone.maxLightness));
  // Hue matters for luminance (yellow at 36% is far brighter than blue at
  // 36%): step down until white text clears the contrast floor.
  while (hsl.toColor().computeLuminance() > CoverTone.maxLuminance &&
      hsl.lightness > CoverTone.minLightness) {
    hsl = hsl.withLightness(hsl.lightness - CoverTone.lightnessStep);
  }
  return hsl.toColor();
}

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Tuning for [coverPaletteFrom], measured from the reference player.
class CoverTone {
  CoverTone._();

  static const double minLightness = 0.12;
  static const double maxLightness = 0.36;
  static const double maxSaturation = 0.8;

  /// White text on the fill keeps ≥ 6:1 contrast: (1.05) / (L + 0.05).
  static const double maxLuminance = 0.12;
  static const double lightnessStep = 0.02;

  /// Bottom edge: this share of the fill's lightness.
  static const double deepLightness = 0.45;

  static const double glowLightness = 0.4;
  static const double glowMinSaturation = 0.35;
  static const double glowMinHueShift = 25;
  static const double glowHueShift = 40;

  /// Glow strength at its centre.
  static const double glowOpacity = 0.55;

  /// Darkening at the page corners.
  static const double vignette = 0.35;
}

/// Song id → [CoverPalette], computed once per cover in the background.
class PlayerCoverColors {
  PlayerCoverColors._();

  static final palettes = <String, CoverPalette>{}.obs;
  static final _pending = <String>{};

  /// Songs whose cover gives no palette (none, or it failed): nothing to
  /// wait for. Reactive, so a page holding the last palette lets go.
  static final _none = <String>{}.obs;

  /// The palette last painted, held while the next song's is computed.
  static CoverPalette? _lastShown;

  /// Most covers kept; the player only ever needs the current one (and
  /// the next, computed ahead).
  static const _keep = 24;

  /// The palette for [item], or null while it's being computed (or the
  /// item has no cover). Reactive inside an Obx.
  static CoverPalette? of(MediaItem? item) {
    if (item == null) return null;
    final p = palettes[item.id];
    if (p == null) _compute(item);
    return p;
  }

  /// What to paint the page for [item] with: its own palette once ready;
  /// until then the one shown before, so a new song's page eases straight
  /// from the old colours to its own (not through [fallback] first);
  /// [fallback] when there's nothing to wait for. Reactive inside an Obx.
  static CoverPalette shown(MediaItem? item, CoverPalette fallback) {
    final p = of(item);
    if (p != null) return _lastShown = p;
    if (item == null || _none.contains(item.id)) return fallback;
    return _lastShown ?? fallback;
  }

  /// Computes [item]'s palette ahead (the next song), so the page can
  /// change colour together with the cover. Not reactive.
  static void warm(MediaItem? item) {
    if (item == null || palettes.containsKey(item.id)) return;
    _compute(item);
  }

  static Future<void> _compute(MediaItem item) async {
    if (_none.contains(item.id) || !_pending.add(item.id)) return;
    var found = false;
    try {
      final provider = _provider(item);
      if (provider == null) return;
      final g = await PaletteGenerator.fromImageProvider(
          ResizeImage(provider, width: 64, height: 64));
      final dominant = g.dominantColor?.color ??
          g.darkVibrantColor?.color ??
          g.darkMutedColor?.color;
      if (dominant == null) return;
      final secondary = g.vibrantColor?.color ??
          g.lightVibrantColor?.color ??
          g.mutedColor?.color;
      if (palettes.length >= _keep) palettes.remove(palettes.keys.first);
      palettes[item.id] =
          coverPaletteFrom(dominant: dominant, secondary: secondary);
      found = true;
    } catch (e) {
      printERROR('Cover palette failed: $e');
    } finally {
      _pending.remove(item.id);
      // Not straight away: this can run inside a build (via [of]).
      if (!found) Future.microtask(() => _markNone(item.id));
    }
  }

  static void _markNone(String id) {
    if (_none.contains(id)) return;
    if (_none.length >= _keep) _none.remove(_none.first);
    _none.add(id);
  }

  /// Same art the player shows: the saved thumbnail for downloaded songs,
  /// else the cover URL.
  static ImageProvider? _provider(MediaItem item) {
    if ((item.extras?['url'] ?? '').toString().contains('file') &&
        Get.isRegistered<SettingsScreenController>()) {
      final file = File(
          '${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${item.id}.png');
      if (file.existsSync()) return FileImage(file);
    }
    final art = item.artUri?.toString() ?? '';
    if (art.startsWith('file://')) return FileImage(File(art.substring(7)));
    if (art.startsWith('/')) return FileImage(File(art));
    if (art.isEmpty) return null;
    return CachedNetworkImageProvider(Thumbnail(art).medium);
  }
}

/// The full player's page, painted from [palette]: the fill under the
/// cover darkening to [CoverPalette.deep] at the bottom, with the glow
/// behind the transport. Colours ease over ([RiffDurations.colour]) when
/// the song changes; with
/// [drift] (the Player canvas setting) the glow wanders slowly, unless the
/// phone's Remove animations is on.
class CoverBackdrop extends StatefulWidget {
  const CoverBackdrop({super.key, required this.palette, this.drift = false});

  final CoverPalette palette;
  final bool drift;

  @override
  State<CoverBackdrop> createState() => _CoverBackdropState();
}

class _CoverBackdropState extends State<CoverBackdrop>
    with TickerProviderStateMixin {
  static const Duration _driftCycle = Duration(seconds: 18);

  AnimationController? _drift;

  /// The phone's Remove animations (accessibility): the glow holds still.
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncDrift();
  }

  @override
  void didUpdateWidget(covariant CoverBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drift != widget.drift) _syncDrift();
  }

  void _syncDrift() {
    final drift = widget.drift && !_reducedMotion;
    if (drift && _drift == null) {
      _drift = AnimationController(vsync: this, duration: _driftCycle)
        ..repeat(reverse: true);
    } else if (!drift && _drift != null) {
      _drift!.dispose();
      _drift = null;
    }
  }

  @override
  void dispose() {
    _drift?.dispose();
    super.dispose();
  }

  Widget _glow(Color glow, double t) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(
              (t - 0.5) * 0.5,
              0.72 - math.sin(t * math.pi) * 0.12,
            ),
            radius: 0.75,
            colors: [
              glow.withOpacity(CoverTone.glowOpacity),
              glow.withOpacity(0),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          duration: RiffDurations.colour,
          curve: RiffDurations.enterCurve,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.fill, palette.fill, palette.deep],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: palette.glow),
          duration: RiffDurations.colour,
          curve: RiffDurations.enterCurve,
          builder: (context, glow, _) {
            final c = glow ?? palette.glow;
            final drift = _drift;
            if (drift == null) return _glow(c, 0.5);
            return AnimatedBuilder(
              animation: drift,
              builder: (context, _) => _glow(c, drift.value),
            );
          },
        ),
        // Corners darker than the middle, like the reference.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.3),
              radius: 1.25,
              colors: [
                RiffPalette.scrim.withOpacity(0),
                RiffPalette.scrim.withOpacity(CoverTone.vignette),
              ],
              stops: const [0.6, 1],
            ),
          ),
        ),
      ],
    );
  }
}
