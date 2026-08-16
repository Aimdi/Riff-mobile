import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_greeting.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';

/// Home personal-radio card — featured row with a green play control.
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

  MediaItem? _previewArt() {
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
    final recent = StatsService.mostRecentSong();
    if (recent != null) return recent;
    return null;
  }

  Future<void> _playWave() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final ok = await Get.find<PlayerController>().startRiffWave();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'riffWaveEmpty'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final disc = _disc;
    const artSize = 72.0;
    final fill = Color.alphaBlend(accent.withOpacity(0.14), homeTileFill(context));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _starting ? null : _playWave,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Obx(() {
                  Get.find<PlayerController>().currentSong.value;
                  disc?.dailyMixes.length;
                  Get.find<HomeScreenController>().quickPicks.value;
                  final art = _previewArt();
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(RiffTokens.radiusArt),
                    child: art != null
                        ? ImageWidget(
                            song: art,
                            size: artSize,
                            borderRadius: RiffTokens.radiusArt,
                          )
                        : ColoredBox(
                            color: accent.withOpacity(0.22),
                            child: SizedBox(
                              width: artSize,
                              height: artSize,
                              child: Icon(Icons.graphic_eq_rounded,
                                  color: accent, size: 32),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.4,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'riffWaveDes'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: _starting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(
                            Icons.play_arrow_rounded,
                            size: 30,
                            color: Colors.black,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
