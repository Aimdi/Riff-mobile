import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_progress_service.dart';
import '/services/free_audiobook_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_library_controller.dart';
import 'audiobook_play.dart';
import 'audiobook_widgets.dart';
import '/ui/widgets/riff_header_bar.dart';

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
      appBar: RiffAppBar(AppBar(
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
          const SizedBox(width: RiffSpacing.xs),
        ],
      )),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, book)),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(RiffSpacing.x3l),
                child: Center(
                    child: SizedBox.square(
                        dimension: RiffComponentSizes.spinner,
                        child: CircularProgressIndicator(
                            strokeWidth: RiffComponentSizes.spinnerStroke))),
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
          const SliverToBoxAdapter(
              child: SizedBox(height: RiffSpacing.unit * 45)),
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
    final cover = (width * 0.52).clamp(
        RiffComponentSizes.showCoverMin, RiffComponentSizes.showCoverMax);
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter + RiffSpacing.sm,
          right: HomeLayout.gutter + RiffSpacing.sm,
          bottom: RiffSpacing.sm),
      child: Column(
        children: [
          // Show-page header (§ Phase 7): art radius 8, title
          // headlineSmall, author bodyMedium, Play as the primary pill.
          AudiobookCover(url: book.cover, size: cover),
          const SizedBox(height: RiffSpacing.lg),
          Text(
            book.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xs),
            Text(
              book.author,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.xs),
            Text(meta,
                textAlign: TextAlign.center,
                style: homeCardSubtitleStyle(context)),
          ],
          const SizedBox(height: RiffSpacing.lg),
          SizedBox(
            height: RiffSizes.touch,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: d == null || d.chapters.isEmpty ? null : () => _play(),
              icon: const Icon(Icons.play_arrow_rounded),
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
    // § Phase 7: descriptions in bodyLarge.
    final style = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.md,
          right: HomeLayout.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(RiffRadii.sm),
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
                const SizedBox(height: RiffSpacing.xs),
                // A text button look: 15/700 in the accent (§5.5).
                Text(
                  _expanded ? 'showLess'.tr : 'readMore'.tr,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          ),
          if (d.subjects.isNotEmpty) ...[
            const SizedBox(height: RiffSpacing.md),
            // §5.6 unselected chips: transparent with a divider hairline.
            Wrap(
              spacing: RiffSpacing.sm,
              runSpacing: RiffSpacing.sm,
              children: [
                for (final s in d.subjects)
                  Container(
                    height: RiffComponentSizes.chip,
                    alignment: Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                          side: BorderSide(
                              color: Theme.of(context).dividerColor, width: 0)),
                    ),
                    child: Text(
                      s[0].toUpperCase() + s.substring(1),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface),
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
            // Episode-style row: titleMedium (2 lines), accent title and
            // equalizer while playing on an accentMuted tint, 2 px progress,
            // full-width hairline inside the bottom edge.
            return Material(
              color: playing
                  ? RiffColors.of(context).accentMuted
                  : Colors.transparent,
              child: InkWell(
                onTap: () => _play(index: i),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: HomeLayout.gutter,
                          vertical: RiffSpacing.md),
                      child: Row(
                        children: [
                          SizedBox(
                            width: RiffSpacing.x3l,
                            child: playing
                                ? Icon(Icons.graphic_eq_rounded,
                                    size: RiffComponentSizes.trailingIcon,
                                    color: accent)
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
                                      .titleMedium
                                      ?.copyWith(
                                        color: playing
                                            ? accent
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
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
                            compactEpisodeLength(c.durationSec.round()),
                            style: homeCardSubtitleStyle(context),
                          ),
                        ],
                      ),
                    ),
                    const RiffRowHairline(),
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
      padding: const EdgeInsets.all(RiffSpacing.x3l),
      child: Column(
        children: [
          Text('bookLoadFailed'.tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: RiffSpacing.sm),
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
