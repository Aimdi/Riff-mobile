import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';
import 'package:hive/hive.dart';

/// Home hero: one-tap personal radio (Yandex/Apple “Wave” energy).
class RiffWaveHero extends StatefulWidget {
  const RiffWaveHero({super.key});

  @override
  State<RiffWaveHero> createState() => _RiffWaveHeroState();
}

class _RiffWaveHeroState extends State<RiffWaveHero> {
  bool _starting = false;

  DiscoveryService? get _disc => Get.isRegistered<DiscoveryService>()
      ? Get.find<DiscoveryService>()
      : null;

  MediaItem? _artSeed() {
    final player = Get.find<PlayerController>();
    if (player.currentSong.value != null) return player.currentSong.value;
    final mixes = _disc?.dailyMixes;
    if (mixes != null && mixes.isNotEmpty && mixes.first.tracks.isNotEmpty) {
      try {
        return MediaItemBuilder.fromJson(mixes.first.tracks.first);
      } catch (_) {}
    }
    final qp = Get.find<HomeScreenController>().quickPicks.value.songList;
    if (qp.isNotEmpty) return qp.first;
    return null;
  }

  Future<MediaItem?> _resolveSeed() async {
    final art = _artSeed();
    if (art != null) return art;
    final recentId = Hive.box('AppPrefs').get('recentSongId');
    if (recentId is String && recentId.isNotEmpty) {
      return MediaItem(id: recentId, title: 'Radio');
    }
    return null;
  }

  Future<void> _playWave() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final seed = await _resolveSeed();
      if (seed == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'mixEmpty'.tr,
          size: SanckBarSize.MEDIUM,
        ));
        return;
      }
      final player = Get.find<PlayerController>();
      await player.startRadio(
        DiscoveryService.withSource(seed, DiscoverySource.radio),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        'networkError'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _exploreLabel(double v) {
    if (v < 0.33) return 'familiar'.tr;
    if (v > 0.66) return 'adventurous'.tr;
    return 'balanced'.tr;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final disc = _disc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withOpacity(0.28),
              theme.cardColor.withOpacity(0.95),
              theme.scaffoldBackgroundColor,
            ],
          ),
          border: Border.fromBorderSide(RiffTokens.hairlineBorder(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Obx(() {
                    Get.find<PlayerController>().currentSong.value;
                    disc?.dailyMixes.length;
                    final art = _artSeed();
                    return ClipRRect(
                      borderRadius:
                          BorderRadius.circular(RiffTokens.radiusSm),
                      child: art != null
                          ? ImageWidget(song: art, size: 64)
                          : ColoredBox(
                              color: accent.withOpacity(0.2),
                              child: SizedBox(
                                width: 64,
                                height: 64,
                                child: Icon(Icons.graphic_eq_rounded,
                                    color: accent, size: 30),
                              ),
                            ),
                    );
                  }),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'riffWave'.tr,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 22,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'riffWaveDes'.tr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _starting ? null : _playWave,
                    icon: _starting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 26),
                    label: Text('play'.tr),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
              if (disc != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'familiar'.tr,
                      style: theme.textTheme.labelSmall,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                        ),
                        child: Slider(
                          value: disc.exploration.clamp(0.0, 1.0),
                          onChanged: (nv) {
                            disc.exploration = nv;
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    Text(
                      'adventurous'.tr,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    '${'exploration'.tr}: ${_exploreLabel(disc.exploration)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
