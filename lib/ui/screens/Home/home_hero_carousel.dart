import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_layout.dart';

/// Quick picks as a compact centred carousel (Echo Music's hero carousel,
/// scaled down): one card in the middle, neighbours peeking in on both
/// sides, pages snap, and it moves on by itself every five seconds (never
/// while the user is scrolling). Sits under a section title further down
/// Home.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.songs,
    this.source = DiscoverySource.home,
  });

  final List<MediaItem> songs;
  final DiscoverySource source;

  static const maxItems = 12;

  /// Card size: a little wider than tall, about half the phone width.
  static const cardWidth = 230.0;
  static const height = 200.0;

  /// Echo: `itemSpacing = 8.dp`.
  static const spacing = 8.0;

  /// Keep the strip phone-sized on tablets.
  static const maxWidth = 640.0;

  static const autoAdvance = Duration(seconds: 5);

  /// Share of the viewport one page takes (card plus its spacing); the
  /// rest is the neighbours peeking in either side.
  static double viewportFraction(double width) =>
      ((cardWidth + spacing) / width).clamp(0.3, 1.0);

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  PageController? _page;
  double _fraction = 0;
  Timer? _timer;

  List<MediaItem> get _songs {
    final seen = <String>{};
    return widget.songs
        .where((s) => seen.add(s.id))
        .take(HomeHeroCarousel.maxItems)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(HomeHeroCarousel.autoAdvance, (_) => _advance());
  }

  PageController _controllerFor(double width) {
    final fraction = HomeHeroCarousel.viewportFraction(width);
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

  void _advance() {
    final page = _page;
    if (!mounted || page == null || !page.hasClients) return;
    if (page.position.isScrollingNotifier.value) return;
    final count = _songs.length;
    if (count < 2) return;
    final next = ((page.page ?? 0).round() + 1) % count;
    page.animateToPage(next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page?.dispose();
    super.dispose();
  }

  Future<void> _play(List<MediaItem> songs, int i) async {
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
    final songs = _songs;
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeSectionHeader('quickpicks'.tr),
        LayoutBuilder(builder: (context, constraints) {
          final width =
              math.min(constraints.maxWidth, HomeHeroCarousel.maxWidth);
          final controller = _controllerFor(width);
          return Center(
            child: SizedBox(
              width: width,
              height: HomeHeroCarousel.height,
              child: PageView.builder(
                controller: controller,
                physics: const _SnappingPhysics(),
                itemCount: songs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: HomeHeroCarousel.spacing / 2),
                  child: _HeroCard(
                    song: songs[i],
                    onTap: () => _play(songs, i),
                    onLongPress: () => showCurrentSongSheet(
                        song: songs[i],
                        context: Get.find<PlayerController>()
                            .homeScaffoldkey
                            .currentContext),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Page snapping with a little more drag than the default, so a flick
/// moves one card, not three.
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
      {required this.song, required this.onTap, required this.onLongPress});
  final MediaItem song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const radius = 22.0;

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final theme = Theme.of(context);
    return Material(
      color: homeTileColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        // Echo: 1dp outlineVariant border.
        side: BorderSide(
            color: (homeMutedColor(context) ?? Colors.grey).withOpacity(0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, c) => ImageWidget(
                  song: song,
                  size: math.max(c.maxWidth, c.maxHeight),
                  borderRadius: 0),
            ),
            // Echo: transparent → transparent → black 70%.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xB3000000)
                  ],
                ),
              ),
            ),
            Obx(() {
              final playing = player.currentSong.value?.id == song.id &&
                  player.buttonState.value == PlayButtonState.playing;
              if (!playing) return const SizedBox.shrink();
              return Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      size: 18, color: Colors.black),
                ),
              );
            }),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  if ((song.artist ?? '').isNotEmpty)
                    Text(song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xB3FFFFFF))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
