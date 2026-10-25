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

  /// Quick picks: the large item, leaving a 48dp sliver of the next; on
  /// a tablet no wider than [RiffSizes.carouselItemMax], so more than one
  /// shows (Apple Music's Top picks) instead of one pane-wide card.
  double get carouselItem {
    final item = inner - RiffSizes.carouselSpacing - RiffSizes.carouselPeek;
    return item > RiffSizes.carouselItemMax ? RiffSizes.carouselItemMax : item;
  }

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

/// Section title style: the theme's titleLarge in onSurface.
TextStyle riffSectionTitleStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.titleLarge ?? const TextStyle())
      .copyWith(color: theme.colorScheme.onSurface);
}

/// Muted secondary text on Home.
Color riffMuted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Shared Home section header: 24dp above, a 48dp title row in sentence
/// case, then 8dp to the content. An optional [kicker] sits above the
/// title and an optional [art] before both (the artist or song a shelf is
/// about, as YouTube Music and Spotify show it); [onSeeAll] adds a 48dp
/// chevron, [action] any other trailing button (Quick picks' "Play all").
class RiffSectionHeader extends StatelessWidget {
  const RiffSectionHeader(
    this.title, {
    super.key,
    this.kicker,
    this.art,
    this.titleIsName = false,
    this.onSeeAll,
    this.onTitleTap,
    this.action,
    this.top = RiffSpacing.section,
  });

  final String title;
  final String? kicker;
  final Widget? art;

  /// The title is a name (an artist, a song): it keeps its capitals.
  final bool titleIsName;
  final VoidCallback? onSeeAll;

  /// What the title (and its picture) open of their own: the artist a
  /// shelf is like, as YouTube Music's header links it. Without it the
  /// title opens [onSeeAll], as Spotify's and Apple Music's do.
  final VoidCallback? onTitleTap;
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
                // "See all" is a link: accent (§2.5).
                color: theme.colorScheme.primary,
                constraints: const BoxConstraints.tightFor(
                    width: RiffSizes.touch, height: RiffSizes.touch),
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: onSeeAll,
              ));
    return Padding(
      padding: EdgeInsets.only(
          left: RiffSpacing.gutter,
          top: top,
          right: trailing == null ? RiffSpacing.gutter : RiffSpacing.xs,
          bottom: RiffSpacing.headerToContent),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RiffSpacing.headerRow),
        child: Row(
          children: [
            Expanded(child: _lead(context, theme)),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// The picture, the line and the title; tappable when they open
  /// something ([onTitleTap], else [onSeeAll]).
  Widget _lead(BuildContext context, ThemeData theme) {
    final heading = Semantics(
      header: true,
      // A button for TalkBack only when it opens something of its own: for
      // See all the chevron is that button.
      button: onTitleTap != null,
      onTap: onTitleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kicker != null && kicker!.isNotEmpty)
            Text(
              kicker!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: riffMuted(context)),
            ),
          // A name ("Because you liked" a song) may take a second line on a
          // phone rather than lose its end.
          Text(
            titleIsName ? title : homeSentenceCase(title),
            maxLines: titleIsName ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: riffSectionTitleStyle(context),
          ),
        ],
      ),
    );
    final lead = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RiffSpacing.headerRow),
      child: Row(
        children: [
          if (art != null) ...[
            art!,
            const SizedBox(width: RiffSpacing.md),
          ],
          Expanded(child: heading),
        ],
      ),
    );
    final tap = onTitleTap ?? onSeeAll;
    if (tap == null) return lead;
    return InkWell(
      excludeFromSemantics: true,
      borderRadius: BorderRadius.circular(RiffSizes.tileRadius),
      onTap: tap,
      child: lead,
    );
  }
}
