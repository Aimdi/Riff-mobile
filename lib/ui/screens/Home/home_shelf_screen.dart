import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/media_item_extras.dart';
import '/services/spotify_import_service.dart' show SpotifyTrackRef;
import '/ui/navigator.dart';
import '/ui/theme/riff_tokens.dart';
import 'home_feed_builder.dart';
import 'home_layout.dart';
import 'home_metrics.dart';
import 'home_shelves.dart';

/// Opens [shelf]'s "See all" page.
void openHomeShelf(HomeShelfData shelf) => Get.toNamed(
      ScreenNavigationSetup.homeShelfScreen,
      id: ScreenNavigationSetup.id,
      arguments: shelf,
    );

/// Every card of a Home shelf in a grid, as Spotify's Show all and Apple
/// Music's See All open a section: two columns on a phone, more on a
/// tablet; videos and episodes one per row on a phone. The cards are the
/// shelf's own (tap, long press, cover flight).
class HomeShelfScreen extends StatelessWidget {
  const HomeShelfScreen({super.key, required this.shelf});

  final HomeShelfData shelf;

  /// Columns and card width for a pane [inner] wide.
  static ({int columns, double card}) grid(HomeShelfData shelf, double inner) {
    final wide = shelf.kind == HomeShelfKind.videos ||
        shelf.items.any((i) =>
            i.value is MediaItem && (i.value as MediaItem).isPodcastEpisode);
    final target = wide
        ? RiffComponentSizes.shelfGridWide
        : RiffComponentSizes.shelfGridCard;
    const gap = RiffSpacing.cardGap;
    var columns = ((inner + gap) / (target + gap)).floor();
    if (columns < (wide ? 1 : 2)) columns = wide ? 1 : 2;
    return (columns: columns, card: (inner - gap * (columns - 1)) / columns);
  }

  @override
  Widget build(BuildContext context) {
    final items = shelf.items;
    final songs = [
      for (final i in items)
        if (i.value is MediaItem) i.value as MediaItem
    ];
    final spotifySongs = [
      for (final i in items)
        if (i.value is SpotifyTrackRef) i.value as SpotifyTrackRef
    ];
    final kicker = shelf.kicker;
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RiffPageHeader(
            shelf.titleIsName ? shelf.title : homeSentenceCase(shelf.title),
            subtitle: kicker == null || kicker.isEmpty ? null : kicker,
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final metrics = HomeMetrics(box.maxWidth);
              final (:columns, :card) = grid(shelf, metrics.inner);
              final text = ShelfCardSize.textBlock(context);
              var extent = 0.0;
              for (final i in items) {
                final v = i.value;
                final h = v is MediaItem && v.isPodcastEpisode
                    ? ShelfCardSize.episodeHeight(context)
                    : ShelfCardSize.artHeightAt(v, shelf.kind, card) + text;
                if (h > extent) extent = h;
              }
              return GridView.builder(
                padding: EdgeInsets.only(
                    left: RiffSpacing.gutter,
                    right: RiffSpacing.gutter,
                    top: RiffSpacing.sm,
                    bottom: homeBottomPadding(context)),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: RiffSpacing.cardGap,
                  mainAxisSpacing: RiffSpacing.lg,
                  mainAxisExtent: extent,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => HomeShelfItem(
                  value: items[i].value,
                  kind: shelf.kind,
                  metrics: metrics,
                  queue: songs,
                  spotifyQueue: spotifySongs,
                  width: card,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
