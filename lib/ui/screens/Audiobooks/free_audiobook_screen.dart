import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_progress_service.dart';
import '/services/free_audiobook_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_library_controller.dart';
import 'audiobook_play.dart';
import 'audiobook_widgets.dart';

/// A free LibriVox book: cover, play / resume, about, and its chapters.
class FreeAudiobookScreen extends StatefulWidget {
  const FreeAudiobookScreen({super.key, required this.book});
  final FreeAudiobook book;

  @override
  State<FreeAudiobookScreen> createState() => _FreeAudiobookScreenState();
}

class _FreeAudiobookScreenState extends State<FreeAudiobookScreen> {
  FreeAudiobookDetail? _detail;
  bool _loading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await FreeAudiobookService.detail(widget.book.id);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
    });
  }

  Future<void> _play({int? index}) async {
    final d = _detail;
    if (d == null) return;
    await playFreeAudiobook(d, index: index);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final book = _detail?.book ?? widget.book;
    final lib = Get.find<AudiobookLibraryController>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Obx(() {
            final saved = lib.isFreeSaved(widget.book.id);
            return IconButton(
              tooltip: saved ? 'saved'.tr : 'save'.tr,
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: saved ? Theme.of(context).colorScheme.secondary : null,
              ),
              onPressed: () => lib.toggleFree(_detail?.book ?? widget.book),
            );
          }),
          const SizedBox(width: 4),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, book)),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                    child: SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5))),
              ),
            )
          else if (_detail == null || _detail!.chapters.isEmpty)
            SliverToBoxAdapter(child: _error(context))
          else ...[
            if (_detail!.description.isNotEmpty)
              SliverToBoxAdapter(child: _about(context, _detail!)),
            SliverToBoxAdapter(child: HomeSectionHeader('chapters'.tr)),
            _chapters(context, _detail!),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter,
                    top: RiffSpacing.xl,
                    right: HomeLayout.gutter),
                child: Text(
                  'publicDomainNote'.tr,
                  style: homeCardSubtitleStyle(context),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 180)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, FreeAudiobook book) {
    final theme = Theme.of(context);
    final d = _detail;
    final last = AudiobookProgressService.lastTrackForBook(book.id);
    final lastIdx = (last?['trackIndex'] as num?)?.toInt();
    final meta = d == null
        ? ''
        : episodeMetaLine([
            audiobookChapterCount(d.chapters.length),
            compactEpisodeLength(d.totalSec.round()),
            d.language,
          ]);
    final width = MediaQuery.sizeOf(context).width;
    final cover = (width * 0.52).clamp(160.0, 240.0);
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter + RiffSpacing.sm,
          right: HomeLayout.gutter + RiffSpacing.sm,
          bottom: RiffSpacing.sm),
      child: Column(
        children: [
          AudiobookCover(
              url: book.cover, size: cover, radius: RiffTokens.radiusMd),
          const SizedBox(height: 18),
          Text(
            book.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(height: 1.2),
          ),
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              book.author,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(meta,
                textAlign: TextAlign.center,
                style: homeCardSubtitleStyle(context)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: RiffSurfaces.voidBlack,
                disabledBackgroundColor:
                    theme.colorScheme.secondary.withOpacity(0.35),
                shape: const StadiumBorder(),
                textStyle: theme.textTheme.titleMedium,
              ),
              onPressed: d == null || d.chapters.isEmpty ? null : () => _play(),
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: Text(
                lastIdx != null && d != null
                    ? '${'resume'.tr} · ${'chapterOf'.trParams({
                            'n': '${lastIdx + 1}',
                            'total': '${d.chapters.length}'
                          })}'
                    : 'play'.tr,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _about(BuildContext context, FreeAudiobookDetail d) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(height: 1.45, color: homeMutedColor(context));
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.md,
          right: HomeLayout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.description,
                  maxLines: _expanded ? null : 4,
                  overflow:
                      _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: style,
                ),
                const SizedBox(height: 4),
                Text(
                  _expanded ? 'showLess'.tr : 'readMore'.tr,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).textTheme.titleMedium?.color,
                      ),
                ),
              ],
            ),
          ),
          if (d.subjects.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in d.subjects)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: homeTileColor(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      s[0].toUpperCase() + s.substring(1),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chapters(BuildContext context, FreeAudiobookDetail d) {
    final player = Get.isRegistered<PlayerController>()
        ? Get.find<PlayerController>()
        : null;
    final accent = Theme.of(context).colorScheme.secondary;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final c = d.chapters[i];
          final id = '$freeAudiobookIdPrefix${d.book.id}_${c.index}';
          Widget row(bool playing) {
            final p = AudiobookProgressService.progress(id);
            return InkWell(
              onTap: () => _play(index: i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: HomeLayout.gutter, vertical: RiffSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: playing
                          ? Icon(Icons.graphic_eq_rounded,
                              size: 20, color: accent)
                          : Text(
                              '${i + 1}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: playing
                                      ? accent
                                      : Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.color,
                                ),
                          ),
                          if (p != null && p > 0.02 && p < 0.98) ...[
                            const SizedBox(height: 6),
                            FractionallySizedBox(
                              widthFactor: 0.5,
                              alignment: Alignment.centerLeft,
                              child: PodcastProgressBar(value: p),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      compactEpisodeLength(c.durationSec.round()),
                      style: homeCardSubtitleStyle(context),
                    ),
                  ],
                ),
              ),
            );
          }

          if (player == null) return row(false);
          return Obx(() => row(player.currentSong.value?.id == id));
        },
        childCount: d.chapters.length,
      ),
    );
  }

  Widget _error(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text('bookLoadFailed'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('retry'.tr),
          ),
        ],
      ),
    );
  }
}
