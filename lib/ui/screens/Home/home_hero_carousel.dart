import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_layout.dart';

/// Compact hero carousel (Echo Music's Quick picks): the centred cover is
/// full size, its neighbours shrink and dim at the edges, the title sits
/// over the art, and it moves on by itself every few seconds until touched.
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.title,
    required this.songs,
    this.source = DiscoverySource.home,
  });

  final String title;
  final List<MediaItem> songs;
  final DiscoverySource source;

  static const maxItems = 12;

  /// Share of the width the centred card takes.
  static const viewport = 0.72;

  static const autoAdvance = Duration(seconds: 5);

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  final _page = PageController(viewportFraction: HomeHeroCarousel.viewport);
  Timer? _timer;
  bool _userTouched = false;

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

  void _advance() {
    if (!mounted || _userTouched || !_page.hasClients) return;
    final count = _songs.length;
    if (count < 2) return;
    final next = ((_page.page ?? 0).round() + 1) % count;
    _page.animateToPage(next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
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
      children: [
        HomeSectionHeader(widget.title),
        LayoutBuilder(builder: (context, constraints) {
          final card = constraints.maxWidth * HomeHeroCarousel.viewport;
          // Shorter than wide: big enough to lead the page, small enough
          // that the next section shows on the first screen.
          final height = (card * 0.82).clamp(160.0, 260.0);
          return SizedBox(
            height: height,
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (n) {
                if (n.dragDetails != null) _userTouched = true;
                return false;
              },
              // Pages start at the left gutter (no empty space before the
              // first card); the next one peeks in on the right.
              child: PageView.builder(
                controller: _page,
                padEnds: false,
                itemCount: songs.length,
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _page,
                  builder: (context, child) {
                    final page = _page.hasClients && _page.position.haveDimensions
                        ? (_page.page ?? 0)
                        : 0.0;
                    final distance = (page - i).abs().clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: 1 - distance * 0.14,
                      child: Opacity(opacity: 1 - distance * 0.35, child: child),
                    );
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: i == 0 ? HomeLayout.gutter : 5, right: 5),
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
            ),
          );
        }),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard(
      {required this.song, required this.onTap, required this.onLongPress});
  final MediaItem song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    return Material(
      color: homeTileColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
        side: BorderSide(
            color: (homeMutedColor(context) ?? Colors.grey).withOpacity(0.25)),
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
                  song: song, size: c.maxWidth, borderRadius: 0),
            ),
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
                top: 10,
                right: 10,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq_rounded,
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
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  if ((song.artist ?? '').isNotEmpty)
                    Text(song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, color: Color(0xB3FFFFFF))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
