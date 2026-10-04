import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';

export '/ui/theme/riff_spacing.dart';
import 'home_feed_builder.dart' show homeSentenceCase;

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
                        // labelMedium: 12/16, medium weight. Spelled out
                        // because some Riff themes leave it unset.
                        style:
                            (theme.textTheme.labelMedium ?? const TextStyle())
                                .copyWith(
                          fontSize: 12,
                          height: 16 / 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                          color: riffMuted(context),
                        ),
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
