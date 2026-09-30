import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/screens/Home/home_layout.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';

/// Home personal-radio card: cover, title, round play, mood switch.
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
      // The controller is disposed with the widget — only touch it if still
      // mounted (the play call can outlive the home screen).
      if (mounted) {
        _playPulse
          ..stop()
          ..value = 0;
        setState(() => _starting = false);
      }
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
    const artSize = 64.0;
    final surface = homeTileColor(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HomeLayout.gutter, 16, HomeLayout.gutter, 0),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(accent.withOpacity(0.30), surface),
                surface,
              ],
            ),
          ),
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
                              ? ImageWidget(
                                  song: art, size: artSize, borderRadius: 0)
                              : ColoredBox(
                                  color: accent.withOpacity(0.18),
                                  child: SizedBox.square(
                                    dimension: artSize,
                                    child: Icon(Icons.graphic_eq_rounded,
                                        color: accent, size: 30),
                                  ),
                                ),
                        );
                      }),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.graphic_eq_rounded,
                                    size: 18, color: accent),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'riffWave'.tr,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        homeSectionTitleStyle(context).copyWith(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'riffWaveDes'.tr,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: homeCardSubtitleStyle(context)
                                  .copyWith(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PlayButton(
                        accent: accent,
                        starting: _starting,
                        pulse: _playPulse,
                        onTap: _playWave,
                      ),
                    ],
                  ),
                  if (disc != null) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      // Don't stretch three short labels across a tablet.
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _MoodSelector(
                        exploration: explore,
                        onSelected: _setExploration,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round accent play button; pulses a spinner while the station builds.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
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
    return Material(
      color: accent,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: starting ? null : onTap,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: starting
                ? ScaleTransition(
                    scale: Tween<double>(begin: 0.88, end: 1.08).animate(
                        CurvedAnimation(
                            parent: pulse, curve: Curves.easeInOut)),
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.black,
                      ),
                    ),
                  )
                : Tooltip(
                    message: 'play'.tr,
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 30,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Familiar / Balanced / Adventurous as one segmented control.
class _MoodSelector extends StatelessWidget {
  const _MoodSelector({required this.exploration, required this.onSelected});

  final double exploration;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final options = <(String, double, bool)>[
      ('familiar'.tr, 0.15, exploration < 0.33),
      ('balanced'.tr, 0.5, exploration >= 0.33 && exploration <= 0.66),
      ('adventurous'.tr, 0.85, exploration > 0.66),
    ];
    return Row(
      children: [
        Text(
          'waveMood'.tr,
          style: homeCardSubtitleStyle(context).copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withOpacity(0.28)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                for (final (label, value, selected) in options)
                  Expanded(
                    child: _MoodSegment(
                      label: label,
                      selected: selected,
                      onTap: () => onSelected(value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MoodSegment extends StatelessWidget {
  const _MoodSegment({
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
    final isDark = theme.brightness == Brightness.dark;
    final selectedFill =
        isDark ? Colors.white.withOpacity(0.14) : theme.cardColor;
    return AnimatedContainer(
      duration: RiffTokens.quick,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? selectedFill : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.textTheme.titleMedium?.color
                  : homeMutedColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
