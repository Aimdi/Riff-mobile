import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '../Home/home_layout.dart';

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
      color: homeTileColor(context),
      child: Icon(Icons.podcasts_rounded,
          size: size * 0.42, color: homeMutedColor(context)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size >= 56 ? 8 : 6),
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
                placeholder: (_, __) => ColoredBox(
                    color: theme.colorScheme.onSurface.withOpacity(0.06)),
                errorWidget: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

/// Thin accent progress line used for in-progress episodes.
class PodcastProgressBar extends StatelessWidget {
  const PodcastProgressBar({super.key, required this.value, this.height = 3});

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
        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.14),
        valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
      ),
    );
  }
}

/// One episode in a list: art, two-line title, a muted meta line, optional
/// progress and a round play button. Used by Inbox and Downloads-style lists.
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
    final p = progress;
    return InkWell(
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
            leading ?? PodcastArt(url: artUrl, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: homeMutedColor(context)),
                    ),
                  ],
                  if (p != null && p > 0 && p < 1) ...[
                    const SizedBox(height: 7),
                    FractionallySizedBox(
                      widthFactor: 0.6,
                      alignment: Alignment.centerLeft,
                      child: PodcastProgressBar(value: p),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            trailing ?? PodcastPlayButton(onPressed: onTap),
          ],
        ),
      ),
    );
  }
}

/// Round outlined play button for episode rows.
class PodcastPlayButton extends StatelessWidget {
  const PodcastPlayButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    return IconButton(
      onPressed: onPressed,
      icon: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: (fg ?? theme.colorScheme.onSurface).withOpacity(0.35)),
        ),
        child: Icon(Icons.play_arrow_rounded, size: 22, color: fg),
      ),
    );
  }
}

/// "Continue listening" card: art, title, show, progress and time left, on
/// a raised tile. Lives on a horizontal shelf above the latest episodes.
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

  static const double width = 280;

  /// Card height grown with the system text size.
  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 20 +
        scaler.scale(13.5) * 1.25 * 2 +
        4 +
        scaler.scale(12) * 1.25 +
        12 +
        3;
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
    final accent = scheme.secondary;
    return SizedBox(
      width: width,
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Stack(
                  children: [
                    PodcastArt(url: artUrl, size: 64),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded,
                            size: 18, color: scheme.onPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            homeCardTitleStyle(context).copyWith(height: 1.25),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        episodeMetaLine([show, timeLeft]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardSubtitleStyle(context),
                      ),
                      const SizedBox(height: 8),
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
