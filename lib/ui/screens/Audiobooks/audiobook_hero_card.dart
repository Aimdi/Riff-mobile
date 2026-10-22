import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart' show compactEpisodeLength;

/// The book you're in the middle of, large, as Audible opens the library
/// on it: the cover, title and author, how long is left with a progress
/// bar, and a play button. Tap (or the button) picks it up; long press
/// opens the book's page when [onLongPress] is given.
class AudiobookHeroCard extends StatelessWidget {
  const AudiobookHeroCard({
    super.key,
    required this.cover,
    required this.title,
    required this.progress,
    required this.onPlay,
    this.author = '',
    this.detail = '',
    this.secondsLeft,
    this.onLongPress,
  });

  /// The book's art, [RiffComponentSizes.heroBookCover] square.
  final Widget cover;
  final String title;
  final String author;

  /// A line under the author (the chapter, for a free book).
  final String detail;

  /// 0–1 of the book listened to.
  final double progress;

  /// Time left in the book, when known.
  final int? secondsLeft;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = homeMutedColor(context);
    final left = secondsLeft == null ? '' : compactEpisodeLength(secondsLeft!);
    final leftLabel = left.isEmpty ? '' : '$left ${'left'.tr}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.gutter),
      child: Semantics(
        button: true,
        label: [
          title,
          if (author.isNotEmpty) author,
          if (leftLabel.isNotEmpty) leftLabel,
        ].join(', '),
        excludeSemantics: true,
        child: RiffPressScale(
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(RiffRadii.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPlay,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.all(RiffSpacing.md),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: RiffComponentSizes.heroBookCover,
                      child: cover,
                    ),
                    const SizedBox(width: RiffSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: scheme.onSurface),
                          ),
                          if (author.isNotEmpty) ...[
                            const SizedBox(height: RiffSpacing.xxs),
                            Text(
                              author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: muted),
                            ),
                          ],
                          if (detail.isNotEmpty) ...[
                            const SizedBox(height: RiffSpacing.xxs),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            ),
                          ],
                          const SizedBox(height: RiffSpacing.md),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(RiffRadii.pill),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              minHeight: RiffSizes.progressBar,
                              color: scheme.primary,
                              backgroundColor: scheme.onSurface
                                  .withOpacity(RiffPalette.trackOpacity),
                            ),
                          ),
                          if (leftLabel.isNotEmpty) ...[
                            const SizedBox(height: RiffSpacing.xs),
                            Text(
                              leftLabel,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: RiffSpacing.md),
                    // Play is an accent button (§2.5).
                    Material(
                      color: scheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPlay,
                        child: SizedBox.square(
                          dimension: RiffSizes.touch,
                          child: Icon(Icons.play_arrow_rounded,
                              color: scheme.onPrimary,
                              size: RiffComponentSizes.heroPlayGlyph,
                              semanticLabel: 'resume'.tr),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
