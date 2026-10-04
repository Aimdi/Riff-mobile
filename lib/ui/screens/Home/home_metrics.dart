import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import 'home_feed_builder.dart' show homeSentenceCase;

/// Home spacing scale. Everything lines up 16dp from the rail.
class RiffSpacing {
  RiffSpacing._();

  /// Content margin from the rail's edge and from the right edge.
  static const double gutter = 16;

  /// Space above every section.
  static const double section = 24;

  /// Height of a section's title row.
  static const double headerRow = 48;

  /// Title row to content.
  static const double headerToContent = 8;

  /// Between cards on a shelf.
  static const double cardGap = 12;

  /// Inside grids (Jump back in, Speed dial).
  static const double gridGap = 8;

  /// Riff Wave card to its chip row.
  static const double chipRowTop = 12;
}

/// Home component sizes and corner radii.
class RiffSizes {
  RiffSizes._();

  static const double tileRadius = 8;
  static const double shelfRadius = 12;
  static const double waveRadius = 16;
  static const double carouselRadius = 28;

  static const double jumpTileHeight = 56;
  static const double jumpArt = 48;
  static const double progressBar = 3;

  static const double waveHeight = 88;
  static const double waveArt = 56;
  static const double wavePlay = 48;
  static const double chipRow = 48;
  static const double chipHeight = 40;

  static const double dot = 6;
  static const double dotsTop = 8;

  static const double carouselHeight = 200;
  static const double carouselPeek = 48;
  static const double carouselSpacing = 8;
  static const double carouselPlay = 40;

  static const double artistCircle = 112;
  static const double videoWidth = 224;
  static const double episodeWidth = 280;
  static const double weekHeight = 96;
  static const double touch = 48;
}

/// Sizes worked out from the content pane's width [w] (screen minus rail),
/// never from fixed screen numbers.
class HomeMetrics {
  const HomeMetrics(this.w);

  /// Content pane width.
  final double w;

  /// Inner width between the 16dp margins.
  double get inner => (w - RiffSpacing.gutter * 2).clamp(0, double.infinity);

  /// Jump back in tile: two columns with an 8dp gap.
  double get jumpTile => (inner - RiffSpacing.gridGap) / 2;

  /// Speed dial tile: three columns with 8dp gaps.
  double get speedTile =>
      ((inner - RiffSpacing.gridGap * 2) / 3).clamp(0.0, 160.0);

  /// Quick picks: the large item, leaving a 48dp sliver of the next.
  double get carouselItem =>
      inner - RiffSizes.carouselSpacing - RiffSizes.carouselPeek;

  /// Playlist / album cover: about 2.4 cards per pane, 120–160dp.
  double get shelfCard => ((w - 40) / 2.4).clamp(120.0, 160.0);
}

/// Bottom padding under the feed: the collapsed mini player (which already
/// includes the navigation bar) or just the navigation bar, plus 16dp.
double homeBottomPadding(BuildContext context) {
  final nav = MediaQuery.paddingOf(context).bottom;
  final mini = Get.isRegistered<PlayerController>()
      ? Get.find<PlayerController>().playerPanelMinHeight.value
      : 0.0;
  return (mini > nav ? mini : nav) + 16;
}

/// Section title style: titleLarge, 22/28, bold, onSurface.
TextStyle riffSectionTitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: theme.colorScheme.onSurface,
  );
}

/// Muted secondary text on Home.
Color riffMuted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Shared Home section header: 24dp above, a 48dp title row in sentence
/// case, then 8dp to the content. An optional [kicker] sits above the
/// title; [onSeeAll] adds a 48dp chevron, [action] any other trailing
/// button (Quick picks' "Play all").
class RiffSectionHeader extends StatelessWidget {
  const RiffSectionHeader(
    this.title, {
    super.key,
    this.kicker,
    this.onSeeAll,
    this.action,
    this.top = RiffSpacing.section,
  });

  final String title;
  final String? kicker;
  final VoidCallback? onSeeAll;
  final Widget? action;
  final double top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = action ??
        (onSeeAll == null
            ? null
            : IconButton(
                tooltip: '${'viewAll'.tr}: $title',
                iconSize: 24,
                constraints: const BoxConstraints.tightFor(
                    width: RiffSizes.touch, height: RiffSizes.touch),
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onSeeAll,
              ));
    return Padding(
      padding: EdgeInsets.fromLTRB(
          RiffSpacing.gutter,
          top,
          trailing == null ? RiffSpacing.gutter : 4,
          RiffSpacing.headerToContent),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RiffSpacing.headerRow),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null && kicker!.isNotEmpty)
                      Text(
                        kicker!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: riffMuted(context)),
                      ),
                    Text(
                      homeSentenceCase(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: riffSectionTitleStyle(context),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
