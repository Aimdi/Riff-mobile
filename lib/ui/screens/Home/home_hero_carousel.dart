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

/// Big swipeable covers with the title over the art and the neighbours
/// peeking in at the sides. Tap plays, long-press opens the song menu.
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

  /// How many covers the carousel shows.
  static const maxItems = 8;

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  PageController? _page;
  double _fraction = 0;

  @override
  void dispose() {
    _page?.dispose();
    super.dispose();
  }

  PageController _controllerFor(double fraction) {
    if (_page == null || (_fraction - fraction).abs() > 0.001) {
      _page?.dispose();
      _page = PageController(viewportFraction: fraction);
      _fraction = fraction;
    }
    return _page!;
  }

  Future<void> _play(int i) async {
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(widget.songs, i, source: widget.source);
    if (!ok) snackOperationFailed();
  }

  void _menu(MediaItem song) {
    final player = Get.find<PlayerController>();
    showCurrentSongSheet(
        song: song, context: player.homeScaffoldkey.currentContext);
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs.take(HomeHeroCarousel.maxItems).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(widget.title),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          // One cover with a peek of the next on phones; several on tablets.
          final card = (width * 0.84).clamp(200.0, 360.0);
          final controller = _controllerFor(card / width);
          return SizedBox(
            height: card,
            child: PageView.builder(
              controller: controller,
              padEnds: false,
              itemCount: songs.length,
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(
                    left: i == 0 ? HomeLayout.gutter : HomeLayout.cardGap / 2,
                    right: HomeLayout.cardGap / 2),
                child: _HeroCard(
                  song: songs[i],
                  size: card,
                  onTap: () => _play(i),
                  onLongPress: () => _menu(songs[i]),
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
      {required this.song,
      required this.size,
      required this.onTap,
      required this.onLongPress});
  final MediaItem song;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: homeTileColor(context),
      borderRadius: BorderRadius.circular(RiffTokens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageWidget(song: song, size: size, borderRadius: 0),
            // Fade the lower third so the title reads on any cover.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: Colors.white)),
                  if ((song.artist ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(song.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xDDFFFFFF))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
