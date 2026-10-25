import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_text_metrics.dart';
import '/ui/theme/riff_tokens.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/now_playing_bars.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/songinfo_bottom_sheet.dart';
import 'home_feed_builder.dart';
import 'home_hero_carousel.dart' show HomeHeroCarousel, HomeSnappingPhysics;
import 'home_metrics.dart';
import 'home_shelves.dart' show shelfTitleOpens;
import 'shelf_header_art.dart';

/// A shelf of songs as YouTube Music lays out Quick picks and Listen
/// again: columns of [rows] song rows (cover, title, artist), a column
/// as wide as a Quick picks card with a sliver of the next one showing,
/// paged column by column. Tap plays the shelf from that song (or pauses
/// it when it's the one playing); long press opens the song's menu.
class HomeSongRows extends StatefulWidget {
  const HomeSongRows({
    super.key,
    required this.shelf,
    required this.songs,
    required this.metrics,
  });

  final HomeShelfData shelf;
  final List<MediaItem> songs;
  final HomeMetrics metrics;

  /// Rows in a column.
  static const rows = 4;

  /// Shown as rows when it's a shelf of songs with at least a column's
  /// worth (fewer stay cards).
  static bool fits(HomeShelfData shelf) =>
      shelf.kind == HomeShelfKind.songs &&
      shelf.items.length >= rows &&
      shelf.items.every((i) => i.value is MediaItem);

  /// One row: the cover and two lines of text with 8 dp above and below,
  /// never shorter than the cover with its margin (large system text
  /// grows it).
  static double rowHeight(BuildContext context) {
    final theme = Theme.of(context);
    final text = riffLineHeight(context, theme.textTheme.titleSmall) +
        RiffSpacing.xxs +
        riffLineHeight(context, theme.textTheme.bodyMedium);
    const min = RiffComponentSizes.rowArt + RiffSpacing.sm * 2;
    final h = text + RiffSpacing.sm * 2;
    return h < min ? min : h;
  }

  @override
  State<HomeSongRows> createState() => _HomeSongRowsState();
}

class _HomeSongRowsState extends State<HomeSongRows> {
  PageController? _page;
  double _fraction = 0;

  // The same page share as Quick picks, kept when the pane resizes.
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
    final ok =
        await player.playPlayListSong(songs, i, source: DiscoverySource.home);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs;
    final rowHeight = HomeSongRows.rowHeight(context);
    final columns = (songs.length / HomeSongRows.rows).ceil();
    final rowsShown =
        songs.length < HomeSongRows.rows ? songs.length : HomeSongRows.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        RiffSectionHeader(
          widget.shelf.title,
          kicker: widget.shelf.kicker,
          art: ShelfHeaderArt.of(widget.shelf),
          titleIsName: widget.shelf.titleIsName,
          onTitleTap: shelfTitleOpens(widget.shelf),
          action: TextButton(
            style: TextButton.styleFrom(
                minimumSize: const Size(RiffSizes.touch, RiffSizes.touch)),
            onPressed: () => _play(0),
            child: Text('playAll'.tr),
          ),
        ),
        // Columns scroll out under the left margin but never over the rail.
        ClipRect(
          child: Padding(
            padding: const EdgeInsets.only(left: RiffSpacing.gutter),
            child: SizedBox(
              height: rowHeight * rowsShown,
              child: PageView.builder(
                controller: _controller(),
                padEnds: false,
                clipBehavior: Clip.none,
                physics: const HomeSnappingPhysics(),
                itemCount: columns,
                itemBuilder: (context, c) {
                  final start = c * HomeSongRows.rows;
                  final end = (start + HomeSongRows.rows) > songs.length
                      ? songs.length
                      : start + HomeSongRows.rows;
                  return Padding(
                    padding:
                        const EdgeInsets.only(right: RiffSizes.carouselSpacing),
                    child: Column(
                      children: [
                        for (var i = start; i < end; i++)
                          SizedBox(
                            height: rowHeight,
                            child: _SongRow(
                              song: songs[i],
                              onTap: () => _play(i),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, required this.onTap});
  final MediaItem song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = song.artist ?? '';
    return Semantics(
      button: true,
      label: [song.title, if (artist.isNotEmpty) artist].join(', '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffSizes.tileRadius),
        onTap: onTap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showCurrentSongSheet(
              song: song,
              context:
                  Get.find<PlayerController>().homeScaffoldkey.currentContext);
        },
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RiffRadii.xs),
              child: ImageWidget(
                  song: song, size: RiffComponentSizes.rowArt, borderRadius: 0),
            ),
            const SizedBox(width: RiffSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.onSurface)),
                  const SizedBox(height: RiffSpacing.xxs),
                  Text(artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: riffMuted(context))),
                ],
              ),
            ),
            // The playing song is marked, as on any song row.
            if (Get.isRegistered<PlayerController>())
              Obx(() {
                final playing =
                    Get.find<PlayerController>().currentSong.value?.id ==
                        song.id;
                return playing
                    ? const Padding(
                        padding: EdgeInsets.only(
                            left: RiffSpacing.sm, right: RiffSpacing.sm),
                        child: NowPlayingBars(),
                      )
                    : const SizedBox.shrink();
              }),
          ],
        ),
      ),
    );
  }
}
