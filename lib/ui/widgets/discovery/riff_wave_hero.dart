import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';

/// Home personal-radio card — compact, left-aligned with the rest of Home.
class RiffWaveHero extends StatefulWidget {
  const RiffWaveHero({super.key});

  @override
  State<RiffWaveHero> createState() => _RiffWaveHeroState();
}

class _RiffWaveHeroState extends State<RiffWaveHero>
    with SingleTickerProviderStateMixin {
  bool _starting = false;
  late final AnimationController _playPulse;

  DiscoveryService? get _disc => Get.isRegistered<DiscoveryService>()
      ? Get.find<DiscoveryService>()
      : null;

  @override
  void initState() {
    super.initState();
    _playPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _playPulse.dispose();
    super.dispose();
  }

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
    _playPulse.repeat(reverse: true);
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
      _playPulse
        ..stop()
        ..value = 0;
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _setExploration(double v) async {
    final disc = _disc;
    if (disc == null) return;
    disc.exploration = v;
    setState(() {});
    if (!_starting) await _playWave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final disc = _disc;
    final explore = disc?.exploration ?? 0.5;
    const artSize = 128.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
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
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
                            BorderRadius.circular(RiffTokens.radiusMd),
                        child: art != null
                            ? ImageWidget(song: art, size: artSize)
                            : ColoredBox(
                                color: accent.withOpacity(0.18),
                                child: SizedBox(
                                  width: artSize,
                                  height: artSize,
                                  child: Icon(Icons.graphic_eq_rounded,
                                      color: accent, size: 48),
                                ),
                              ),
                      );
                    }),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'riffWave'.tr,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'riffWaveDes'.tr,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: theme.textTheme.titleSmall?.color
                                  ?.withOpacity(0.78),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _PlayCta(
                            accent: accent,
                            starting: _starting,
                            pulse: _playPulse,
                            onTap: _playWave,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (disc != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'waveMood'.tr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                      letterSpacing: 0.2,
                      color: theme.brightness == Brightness.dark
                          ? RiffSurfaces.textMuted
                          : theme.textTheme.titleSmall?.color
                              ?.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
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

class _PlayCta extends StatelessWidget {
  const _PlayCta({
    required this.accent,
    required this.starting,
    required this.pulse,
    required this.onTap,
  });

  final Color accent;
  final bool starting;
  final AnimationController pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: starting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 18, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: starting
                    ? ScaleTransition(
                        scale: Tween<double>(begin: 0.88, end: 1.08)
                            .animate(CurvedAnimation(
                          parent: pulse,
                          curve: Curves.easeInOut,
                        )),
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.black,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 6),
              Text(
                'play'.tr,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.1,
                ),
              ),
            ],
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
    final isDark = theme.brightness == Brightness.dark;
    final bg = selected
        ? (isDark
            ? RiffSurfaces.elevatedSoft
            : accent.withOpacity(0.12))
        : Colors.transparent;
    final border = selected
        ? accent.withOpacity(0.28)
        : (isDark
            ? RiffSurfaces.hairline.withOpacity(0.55)
            : theme.dividerColor.withOpacity(0.4));
    return Material(
      color: selected && isDark
          ? Color.alphaBlend(accent.withOpacity(0.14), bg)
          : bg,
      shape: StadiumBorder(
        side: BorderSide(color: border, width: RiffTokens.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 11,
              color: selected
                  ? theme.textTheme.titleMedium?.color?.withOpacity(0.92)
                  : (isDark
                      ? RiffSurfaces.textMuted
                      : theme.textTheme.titleSmall?.color?.withOpacity(0.62)),
            ),
          ),
        ),
      ),
    );
  }
}
