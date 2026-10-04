import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_catalog_service.dart';
import '/services/audiobook_progress_service.dart';
import '/services/free_audiobook_service.dart';
import '/ui/theme/palettes/audiobook_genres.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/utils/riff_tokens.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_catalog_detail_screen.dart';
import 'free_audiobook_screen.dart';

/// "1 chapter" / "12 chapters".
String audiobookChapterCount(int n) =>
    n == 1 ? 'chapterCountOne'.tr : 'chapterCount'.trParams({'count': '$n'});

/// Square cover with a quiet book icon while loading or when missing.
class AudiobookCover extends StatelessWidget {
  const AudiobookCover({
    super.key,
    required this.url,
    required this.size,
    this.progress,
    this.radius,
  });

  final String url;
  final double size;

  /// 0–1: thin accent bar along the bottom edge while partly listened.
  final double? progress;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: homeTileColor(context),
      child: Icon(Icons.auto_stories_rounded,
          size: size * 0.36, color: homeMutedColor(context)),
    );
    final p = progress;
    return ClipRRect(
      borderRadius: BorderRadius.circular(
          radius ?? (size >= 100 ? RiffTokens.radiusSm : 6)),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              fallback
            else
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, __) => ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.06)),
                errorWidget: (_, __, ___) => fallback,
              ),
            if (p != null && p > 0.02 && p < 0.98)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: p,
                  minHeight: 3,
                  backgroundColor:
                      RiffColors.of(context).scrim.withOpacity(0.45),
                  valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void openFreeAudiobook(FreeAudiobook book) => Get.to(
      () => FreeAudiobookScreen(book: book),
      transition: Transition.rightToLeft,
    );

void openStoreAudiobook(AudiobookItem book) => Get.to(
      () => AudiobookCatalogDetailScreen(book: book),
      transition: Transition.rightToLeft,
    );

/// Shelf / grid card for a free book.
class FreeAudiobookCard extends StatelessWidget {
  const FreeAudiobookCard({super.key, required this.book, required this.size});
  final FreeAudiobook book;
  final double size;

  @override
  Widget build(BuildContext context) => HomeShelfCard(
        size: size,
        art: AudiobookCover(url: book.cover, size: size, radius: 0),
        title: book.title,
        subtitle: book.author,
        onTap: () => openFreeAudiobook(book),
      );
}

/// Shelf / grid card for a store (Apple → Audible) book.
class StoreAudiobookCard extends StatelessWidget {
  const StoreAudiobookCard({super.key, required this.book, required this.size});
  final AudiobookItem book;
  final double size;

  @override
  Widget build(BuildContext context) => HomeShelfCard(
        size: size,
        art: AudiobookCover(url: book.cover, size: size, radius: 0),
        title: book.title,
        subtitle: book.author,
        onTap: () => openStoreAudiobook(book),
      );
}

/// List row: cover, title, author / meta, and a trailing widget.
class AudiobookRow extends StatelessWidget {
  const AudiobookRow({
    super.key,
    required this.cover,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String cover;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
            left: HomeLayout.gutter,
            top: RiffSpacing.sm,
            right: HomeLayout.gutter - RiffSpacing.xs,
            bottom: RiffSpacing.sm),
        child: Row(
          children: [
            AudiobookCover(url: cover, size: 56),
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).textTheme.titleMedium?.color),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: homeMutedColor(context)),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
      ),
    );
  }
}

/// "Continue listening" card for a free book, from its latest saved
/// chapter record (see [AudiobookProgressService.freeBooksInProgress]).
class FreeAudiobookContinueCard extends StatelessWidget {
  const FreeAudiobookContinueCard(
      {super.key, required this.record, required this.onTap});
  final Map<String, dynamic> record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pos = (record['positionMs'] as num?)?.toInt() ?? 0;
    final dur = (record['durationMs'] as num?)?.toInt() ?? 0;
    final idx = (record['trackIndex'] as num?)?.toInt();
    final count = (record['trackCount'] as num?)?.toInt();
    final chapter = idx == null
        ? ''
        : count != null && count > 0
            ? 'chapterOf'.trParams({'n': '${idx + 1}', 'total': '$count'})
            : '${'chapters'.tr} ${idx + 1}';
    final left = dur > pos ? compactEpisodeLength((dur - pos) ~/ 1000) : '';
    return PodcastContinueCard(
      artUrl: '${record['artUri'] ?? ''}',
      title: '${record['album'] ?? record['title'] ?? ''}',
      show: episodeMetaLine(
          [chapter, left.isEmpty ? null : '$left ${'left'.tr}']),
      progress: dur > 0 ? pos / dur : 0,
      timeLeft: '',
      onTap: onTap,
    );
  }
}

/// Coloured genre tile (same look as the Podcasts "Browse all" tiles).
class AudiobookGenreTile extends StatelessWidget {
  const AudiobookGenreTile(
      {super.key, required this.label, required this.index, this.onTap});
  final String label;
  final int index;
  final VoidCallback? onTap;

  static const _colors = AudiobookGenrePalette.tiles;

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];
    final riff = RiffColors.of(context);
    return Material(
      color: Color.alphaBlend(riff.scrim.withOpacity(0.18), color),
      borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: riff.onImage),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded filled search field used across the Audiobooks tab.
class AudiobookSearchField extends StatelessWidget {
  const AudiobookSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmitted,
    this.onClear,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.xs,
          right: HomeLayout.gutter,
          bottom: RiffSpacing.sm),
      child: SizedBox(
        height: 44,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmitted,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: homeTileColor(context),
            isDense: true,
            contentPadding: EdgeInsets.zero,
            prefixIcon: const Icon(Icons.search_rounded, size: 22),
            suffixIcon: onClear == null
                ? null
                : IconButton(
                    tooltip: 'close'.tr,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClear,
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain sub-heading for search result groups ("Free to listen").
class AudiobookGroupLabel extends StatelessWidget {
  const AudiobookGroupLabel(this.text, {super.key, this.badge});
  final String text;
  final String? badge;

  @override
  Widget build(BuildContext context) =>
      HomeSectionHeader(text, badge: badge, top: 16);
}
