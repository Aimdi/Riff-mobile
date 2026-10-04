import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import '/ui/theme/riff_tokens.dart';
import 'home_metrics.dart';

/// Quick picks as a hero carousel: one large item 16dp from the rail, a
/// 48dp sliver of the next one, 8dp apart, snapping item by item. Title
/// and artist sit on a dark gradient; a 40dp play button bottom-right.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.songs,
    required this.metrics,
    this.source = DiscoverySource.home,
  });

  final List<MediaItem> songs;
  final HomeMetrics metrics;
  final DiscoverySource source;

  /// Page share of the viewport (pane minus the 16dp lead-in) one item
  /// and its spacing take.
  static double viewportFraction(HomeMetrics m) {
    final viewport = m.w - RiffSpacing.gutter;
    if (viewport <= 0) return 1;
    return ((m.carouselItem + RiffSizes.carouselSpacing) / viewport)
        .clamp(0.2, 1.0);
  }

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  PageController? _page;
  double _fraction = 0;

  PageController _controller() {
    final fraction = HomeHeroCarousel.viewportFraction(widget.metrics);
    if (_page == null || (fraction - _fraction).abs() > 0.001) {
      final old = _page;
      final initial = old?.hasClients == true ? (old!.page ?? 0).round() : 0;
      _page = PageController(viewportFraction: fraction, initialPage: initial);
      _fraction = fraction;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _page!;
  }

  @override
  void dispose() {
    _page?.dispose();
    super.dispose();
  }

  Future<void> _play(int i) async {
    final songs = widget.songs;
    final player = Get.find<PlayerController>();
    if (player.currentSong.value?.id == songs[i].id) {
      player.playPause();
      return;
    }
    final ok = await player.playPlayListSong(songs, i, source: widget.source);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader(
          'quickpicks'.tr,
          action: TextButton(
            style: TextButton.styleFrom(
                minimumSize: const Size(48, RiffSizes.touch)),
            onPressed: () => _play(0),
            child: Text('playAll'.tr),
          ),
        ),
        // Items scroll out under the left margin but never over the rail.
        ClipRect(
          child: Padding(
            padding: const EdgeInsets.only(left: RiffSpacing.gutter),
            child: SizedBox(
              height: RiffSizes.carouselHeight,
              child: PageView.builder(
                controller: _controller(),
                padEnds: false,
                clipBehavior: Clip.none,
                physics: const _SnappingPhysics(),
                itemCount: songs.length,
                itemBuilder: (context, i) => Padding(
                  padding:
                      const EdgeInsets.only(right: RiffSizes.carouselSpacing),
                  child: _HeroCard(
                    song: songs[i],
                    onPlay: () => _play(i),
                    onLongPress: () => showCurrentSongSheet(
                        song: songs[i],
                        context: Get.find<PlayerController>()
                            .homeScaffoldkey
                            .currentContext),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Page snapping with a little more drag than the default, so a flick
/// moves one item, not three.
class _SnappingPhysics extends PageScrollPhysics {
  const _SnappingPhysics({super.parent});

  @override
  _SnappingPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnappingPhysics(parent: buildParent(ancestor));

  @override
  double get dragStartDistanceMotionThreshold => 3.5;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard(
      {required this.song, required this.onPlay, required this.onLongPress});
  final MediaItem song;
  final VoidCallback onPlay;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final riff = RiffColors.of(context);
    final player = Get.find<PlayerController>();
    final label = [song.title, if ((song.artist ?? '').isNotEmpty) song.artist]
        .join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RiffSizes.carouselRadius)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          onLongPress: onLongPress,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              fit: StackFit.expand,
              children: [
                ImageWidget(song: song, size: c.maxWidth, borderRadius: 0),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.35, 1],
                      colors: [
                        Colors.transparent,
                        riff.scrim.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16 + RiffSizes.carouselPlay + 8,
                  bottom: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: riff.onImage)),
                      if ((song.artist ?? '').isNotEmpty)
                        Text(song.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: riff.onImage.withOpacity(0.8))),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Obx(() {
                    final playing = player.currentSong.value?.id == song.id &&
                        player.buttonState.value == PlayButtonState.playing;
                    return Material(
                      color: theme.colorScheme.secondary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPlay,
                        child: SizedBox.square(
                          dimension: RiffSizes.carouselPlay,
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 26,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
