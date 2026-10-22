import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/now_playing_bars.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_widgets.dart';
import '/ui/widgets/cover_hero.dart';

/// A book's page looks the same whether the book is a free one or on your
/// Audiobookshelf server, the way Audible and Apple Books lay one out.

/// The cover's size on a book's page: about half the width, within
/// [RiffComponentSizes.showCoverMin]..[RiffComponentSizes.showCoverMax].
double audiobookPageCover(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 0.52).clamp(
        RiffComponentSizes.showCoverMin, RiffComponentSizes.showCoverMax);

/// The top of a book's page: the cover centred and large, the title,
/// author and quieter [lines] under it ("Narrator: …", "12 chapters ·
/// 6h 7m"), then a wide Play / Resume pill.
class AudiobookBookHeader extends StatelessWidget {
  const AudiobookBookHeader({
    super.key,
    required this.cover,
    required this.title,
    required this.author,
    this.lines = const [],
    required this.playLabel,
    this.onPlay,
    this.coverHeroTag,
  });

  /// The cover's address (a file:// one when downloaded).
  final String cover;

  /// The tapped card's cover flying in ([CoverHero.take]); null: none.
  final Object? coverHeroTag;
  final String title;
  final String author;
  final List<String> lines;
  final String playLabel;

  /// Null while there's nothing to play yet (the pill shows disabled).
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter + RiffSpacing.sm,
          right: HomeLayout.gutter + RiffSpacing.sm,
          bottom: RiffSpacing.sm),
      child: Column(
        children: [
          // Show-page header (§ Phase 7): art radius 8, title
          // headlineSmall, author bodyMedium, Play as the primary pill.
          CoverHero(
            tag: coverHeroTag,
            child:
                AudiobookCover(url: cover, size: audiobookPageCover(context)),
          ),
          const SizedBox(height: RiffSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
          if (author.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xs),
            Text(
              author,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          for (final line in lines)
            if (line.isNotEmpty) ...[
              const SizedBox(height: RiffSpacing.xs),
              Text(line,
                  textAlign: TextAlign.center,
                  style: homeCardSubtitleStyle(context)),
            ],
          const SizedBox(height: RiffSpacing.lg),
          // Across a phone; no wider than a cover and a half on a tablet.
          ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: RiffComponentSizes.bookPlayMax),
            child: SizedBox(
              height: RiffSizes.touch,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(playLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A book's description, four lines until More unfolds the rest (no More
/// when it fits), and its [subjects] as chips under it.
class AudiobookAbout extends StatefulWidget {
  const AudiobookAbout({
    super.key,
    required this.description,
    this.subjects = const [],
  });

  final String description;
  final List<String> subjects;

  @override
  State<AudiobookAbout> createState() => _AudiobookAboutState();
}

class _AudiobookAboutState extends State<AudiobookAbout> {
  static const _foldedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // § Phase 7: descriptions in bodyLarge.
    final style = theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.md,
          right: HomeLayout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // More only when there is more: a short description reads
          // whole, with nothing to unfold.
          LayoutBuilder(builder: (context, box) {
            final painter = TextPainter(
              text: TextSpan(text: widget.description, style: style),
              maxLines: _foldedLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: box.maxWidth);
            final folds = painter.didExceedMaxLines;
            painter.dispose();
            if (!folds) return Text(widget.description, style: style);
            return InkWell(
              borderRadius: BorderRadius.circular(RiffRadii.sm),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Read more unfolds the rest (and Show less folds it).
                  AnimatedSize(
                    duration: RiffDurations.select,
                    curve: RiffDurations.selectCurve,
                    alignment: Alignment.topCenter,
                    child: Text(
                      widget.description,
                      maxLines: _expanded ? null : _foldedLines,
                      overflow: _expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  const SizedBox(height: RiffSpacing.xs),
                  // A text button look: 15/700 in the accent (§5.5).
                  Text(
                    _expanded ? 'showLess'.tr : 'readMore'.tr,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            );
          }),
          if (widget.subjects.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.md),
            // §5.6 unselected chips: transparent with a divider hairline.
            Wrap(
              spacing: RiffSpacing.sm,
              runSpacing: RiffSpacing.sm,
              children: [
                for (final s in widget.subjects)
                  Container(
                    height: RiffComponentSizes.chip,
                    padding:
                        const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                          side:
                              BorderSide(color: theme.dividerColor, width: 0)),
                    ),
                    // Centred up and down only: the chip hugs its label.
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        s[0].toUpperCase() + s.substring(1),
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One chapter on a book's page: its number, title (two lines) and
/// length; while it plays, the accent title and moving bars on an
/// accentMuted tint; a thin bar under the title while partly heard.
class AudiobookChapterRow extends StatelessWidget {
  const AudiobookChapterRow({
    super.key,
    required this.number,
    required this.title,
    required this.durationSec,
    this.playing = false,
    this.progress,
    required this.onTap,
  });

  /// 1-based.
  final int number;
  final String title;
  final int durationSec;
  final bool playing;

  /// 0–1: how much of the chapter has been heard.
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    // Episode-style row: titleMedium (2 lines), accent title and
    // equalizer while playing on an accentMuted tint, 2 px progress,
    // full-width hairline inside the bottom edge.
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        color: playing ? RiffColors.of(context).accentMuted : null,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: HomeLayout.gutter, vertical: RiffSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: RiffSpacing.x3l,
                      child: playing
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: NowPlayingBars())
                          : Text(
                              '$number',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: playing
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (p != null && p > 0.02 && p < 0.98) ...[
                            const SizedBox(height: RiffSpacing.sm),
                            FractionallySizedBox(
                              widthFactor: 0.5,
                              alignment: Alignment.centerLeft,
                              child: PodcastProgressBar(value: p),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: RiffSpacing.md),
                    Text(
                      compactEpisodeLength(durationSec),
                      style: homeCardSubtitleStyle(context),
                    ),
                  ],
                ),
              ),
              const RiffRowHairline(),
            ],
          ),
        ),
      ),
    );
  }
}
