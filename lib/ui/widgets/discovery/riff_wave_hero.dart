import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_Item_builder.dart';
import '/services/discovery/discovery_service.dart';
import '/services/stats_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';
import '/ui/screens/Home/home_metrics.dart';
import '/ui/widgets/riff_equalizer.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';

/// Home personal-radio card: cover with a waveform, title, round play.
/// The station chips sit under it ([RiffStationChips]).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final disc = _disc;
    final surface = theme.colorScheme.surfaceContainerHigh;
    final player = Get.find<PlayerController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          RiffSpacing.gutter, RiffSpacing.section, RiffSpacing.gutter, 0),
      child: Semantics(
        button: true,
        label: '${'riffWave'.tr}. ${'riffWaveDes'.tr}',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RiffSizes.waveRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            height: RiffSizes.waveHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(accent.withOpacity(0.28), surface),
                  surface,
                ],
              ),
            ),
            child: InkWell(
              onTap: _starting ? null : _playWave,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Obx(() {
                      player.currentSong.value;
                      final playing =
                          player.buttonState.value == PlayButtonState.playing &&
                              player.playinfrom.value.name == 'riffWave'.tr;
                      disc?.dailyMixes.length;
                      Get.find<HomeScreenController>().quickPicks.value;
                      final art = _previewArt();
                      return ClipRRect(
                        borderRadius:
                            BorderRadius.circular(RiffSizes.tileRadius),
                        child: SizedBox.square(
                          dimension: RiffSizes.waveArt,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (art != null)
                                ImageWidget(
                                    song: art,
                                    size: RiffSizes.waveArt,
                                    borderRadius: 0)
                              else
                                ColoredBox(color: accent.withOpacity(0.22)),
                              const ColoredBox(color: Color(0x66000000)),
                              Center(
                                child: RiffEqualizer(
                                  animate: playing,
                                  color: art != null ? Colors.white : accent,
                                  size: 26,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'riffWave'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'riffWaveDes'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: riffMuted(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PlayButton(
                      accent: accent,
                      starting: _starting,
                      pulse: _playPulse,
                      onTap: _playWave,
                    ),
                  ],
                ),
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
          dimension: RiffSizes.wavePlay,
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
                : const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
          ),
        ),
      ),
    );
  }
}
