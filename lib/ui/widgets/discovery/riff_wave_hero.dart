import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';

/// Home personal-radio card — compact, left-aligned with the rest of Home.
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

  void _setExploration(double v) {
    final disc = _disc;
    if (disc == null) return;
    disc.exploration = v;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final disc = _disc;
    final explore = disc?.exploration ?? 0.5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Material(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
          side: RiffTokens.hairlineBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _starting ? null : _playWave,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Obx(() {
                      Get.find<PlayerController>().currentSong.value;
                      disc?.dailyMixes.length;
                      Get.find<HomeScreenController>().quickPicks.value;
                      final art = _previewArt();
                      return ClipRRect(
                        borderRadius:
                            BorderRadius.circular(RiffTokens.radiusSm),
                        child: art != null
                            ? ImageWidget(song: art, size: 72)
                            : ColoredBox(
                                color: accent.withOpacity(0.18),
                                child: SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: Icon(Icons.graphic_eq_rounded,
                                      color: accent, size: 34),
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
                              fontSize: 20,
                              letterSpacing: -0.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'riffWaveDes'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _starting ? null : _playWave,
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: Center(
                            child: _starting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 32,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (disc != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'waveMood'.tr.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MoodChip(
                        label: 'familiar'.tr,
                        selected: explore < 0.33,
                        onTap: () => _setExploration(0.15),
                      ),
                      _MoodChip(
                        label: 'balanced'.tr,
                        selected: explore >= 0.33 && explore <= 0.66,
                        onTap: () => _setExploration(0.5),
                      ),
                      _MoodChip(
                        label: 'adventurous'.tr,
                        selected: explore > 0.66,
                        onTap: () => _setExploration(0.85),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: accent.withOpacity(0.28),
      backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.55),
      side: BorderSide(
        color: selected ? accent.withOpacity(0.55) : theme.dividerColor,
        width: RiffTokens.hairline,
      ),
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected
            ? theme.textTheme.titleMedium?.color
            : theme.textTheme.titleSmall?.color,
      ),
      shape: const StadiumBorder(),
      showCheckmark: false,
    );
  }
}
