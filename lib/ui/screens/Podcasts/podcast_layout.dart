import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import '/ui/widgets/image_widget.dart';
import '../Home/home_layout.dart';
import '/ui/theme/riff_text_metrics.dart';

/// Episode length for list meta lines: "45m", "1h 35m" (seconds < 1 min
/// round up to "1m"); empty when unknown.
String compactEpisodeLength(int seconds) {
  if (seconds <= 0) return '';
  final totalMin = (seconds / 60).ceil();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "1 show" / "12 shows".
String podcastShowCount(int n) =>
    n == 1 ? 'showCountOne'.tr : 'showCount'.trParams({'count': '$n'});

/// "Show · date · 45m" with empty parts dropped.
String episodeMetaLine(Iterable<String?> parts) =>
    parts.map((p) => (p ?? '').trim()).where((p) => p.isNotEmpty).join(' · ');

/// Rounded square episode / show art from a URL, with a quiet fallback.
class PodcastArt extends StatelessWidget {
  const PodcastArt({super.key, required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Icon(Icons.podcasts_rounded,
          size: size * 0.42, color: theme.colorScheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(RiffRadii.sm),
      child: SizedBox.square(
        dimension: size,
        child: url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                httpHeaders: kCoverImageHeaders,
                fit: BoxFit.cover,
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, __) =>
                    ColoredBox(color: theme.colorScheme.surfaceContainerLow),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// Thin accent progress line on a divider track, for in-progress episodes.
class PodcastProgressBar extends StatelessWidget {
  const PodcastProgressBar(
      {super.key,
      required this.value,
      this.height = RiffComponentSizes.rowProgress});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: theme.dividerColor,
        valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
      ),
    );
  }
}

/// One episode in a list: art, two-line title, a muted meta line, optional
/// progress and a play pill. Used by Inbox and Queue. A full-width hairline
/// is drawn inside the row's bottom edge.
class PodcastEpisodeTile extends StatelessWidget {
  const PodcastEpisodeTile({
    super.key,
    required this.artUrl,
    required this.title,
    required this.meta,
    this.progress,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.trailing,
  });

  final String artUrl;
  final String title;
  final String meta;

  /// 0–1 while partly played; hidden otherwise.
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Replaces the art (e.g. a drag handle + art in the queue).
  final Widget? leading;

  /// Replaces the play button.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.md,
                right: HomeLayout.gutter - RiffSpacing.xs,
                bottom: RiffSpacing.md),
            child: Row(
              children: [
                leading ??
                    PodcastArt(url: artUrl, size: RiffComponentSizes.rowArt),
                const SizedBox(width: RiffSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: RiffSpacing.xxs),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (p != null && p > 0 && p < 1) ...[
                        const SizedBox(height: RiffSpacing.sm),
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          alignment: Alignment.centerLeft,
                          child: PodcastProgressBar(value: p),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: RiffSpacing.xs),
                trailing ?? PodcastPlayButton(onPressed: onTap),
              ],
            ),
          ),
        ),
        // Full-width hairline between episodes (§5.2), inside the row.
        const RiffRowHairline(),
      ],
    );
  }
}

/// Outline play pill for episode rows (§5.5 secondary button look).
class PodcastPlayButton extends StatelessWidget {
  const PodcastPlayButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
        minimumSize: const Size(0, RiffComponentSizes.buttonCompact),
        padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
      ),
      child: const Icon(Icons.play_arrow_rounded,
          size: RiffComponentSizes.trailingIcon),
    );
  }
}

/// "Continue listening" card: art, title, show, progress and time left, on
/// a surface1 tile. Lives on a horizontal shelf above the latest episodes.
class PodcastContinueCard extends StatelessWidget {
  const PodcastContinueCard({
    super.key,
    required this.artUrl,
    required this.title,
    required this.show,
    required this.progress,
    required this.timeLeft,
    this.onTap,
    this.onLongPress,
  });

  static const double width = RiffSizes.episodeWidth;

  /// Inner padding all round.
  static const double _pad = RiffSpacing.md;

  /// Card height grown with the system text size.
  static double heightFor(BuildContext context) {
    return _pad * 2 +
        riffLineHeight(context, homeCardTitleStyle(context)) * 2 +
        RiffSpacing.xs +
        riffLineHeight(context, homeCardSubtitleStyle(context)) +
        RiffSpacing.sm +
        RiffComponentSizes.rowProgress +
        RiffSpacing.xs;
  }

  final String artUrl;
  final String title;
  final String show;
  final double progress;
  final String timeLeft;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffRadii.sm),
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(_pad),
            child: Row(
              children: [
                Stack(
                  children: [
                    PodcastArt(
                        url: artUrl, size: RiffComponentSizes.continueArt),
                    Positioned(
                      right: RiffSpacing.xs,
                      bottom: RiffSpacing.xs,
                      child: Container(
                        width: RiffComponentSizes.continueBadge,
                        height: RiffComponentSizes.continueBadge,
                        decoration: BoxDecoration(
                            color: scheme.primary, shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded,
                            size: RiffComponentSizes.continueBadgeIcon,
                            color: scheme.onPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: RiffSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardTitleStyle(context),
                      ),
                      const SizedBox(height: RiffSpacing.xs),
                      Text(
                        episodeMetaLine([show, timeLeft]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardSubtitleStyle(context),
                      ),
                      const SizedBox(height: RiffSpacing.sm),
                      PodcastProgressBar(value: progress),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
