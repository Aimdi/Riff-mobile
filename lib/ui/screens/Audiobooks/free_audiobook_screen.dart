import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/audiobook_downloads.dart';
import '/services/audiobook_progress_service.dart';
import '/services/free_audiobook_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';
import '/ui/widgets/shimmer_widgets/skeleton_fade.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_download_button.dart';
import 'audiobook_library_controller.dart';
import 'audiobook_play.dart';
import 'audiobook_widgets.dart';
import '/ui/widgets/riff_header_bar.dart';
import '/ui/widgets/now_playing_bars.dart';

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

  /// The book's details and chapters fading in as they replace the spinner.
  final _loadedFade = LoadedRowsFade();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Out of reach (offline): the book as downloaded, which plays from the
    // phone.
    final d = await FreeAudiobookService.detail(widget.book.id) ??
        _downloaded(widget.book);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
    });
  }

  /// The downloaded book [book]: its chapters as they were downloaded.
  static FreeAudiobookDetail? _downloaded(FreeAudiobook book) {
    final chapters = AudiobookDownloads.chapters(book.id);
    if (chapters == null) return null;
    return FreeAudiobookDetail(
      book: book,
      description: '',
      chapters: [
        for (final (i, c) in chapters.indexed)
          FreeAudiobookChapter(
            index: (c.extras?['audiobookTrackIndex'] as num?)?.toInt() ?? i,
            title: c.title,
            url: '${c.extras?['url'] ?? ''}',
            durationSec: (c.duration?.inMilliseconds ?? 0) / 1000,
          ),
      ],
    );
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
    if (_loading) _loadedFade.skeleton();
    return Scaffold(
      appBar: RiffAppBar(AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_detail != null)
            AudiobookDownloadButton(
              bookId: widget.book.id,
              chapters: () => FreeAudiobookService.toMediaItems(_detail!),
            ),
          Obx(() {
            final saved = lib.isFreeSaved(widget.book.id);
            return IconButton(
              tooltip: saved ? 'saved'.tr : 'save'.tr,
              // Saving pops the filled bookmark in.
              icon: RiffSwitcher(
                pop: saved,
                child: Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  key: ValueKey(saved),
                  color: saved ? Theme.of(context).colorScheme.secondary : null,
                ),
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
            SliverToBoxAdapter(child: RiffFadeIn(child: _error(context)))
          else ...[
            if (_detail!.description.isNotEmpty)
              SliverToBoxAdapter(
                  child: _loadedFade.row(_about(context, _detail!))),
            SliverToBoxAdapter(
                child: _loadedFade.row(HomeSectionHeader('chapters'.tr))),
            _chapters(context, _detail!),
            SliverToBoxAdapter(
              child: _loadedFade.row(Padding(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter,
                    top: RiffSpacing.xl,
                    right: HomeLayout.gutter),
                child: Text(
                  'publicDomainNote'.tr,
                  style: homeCardSubtitleStyle(context),
                ),
              )),
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
          AudiobookCover(
              url: AudiobookDownloads.coverOf(book.id) ?? book.cover,
              size: cover),
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
                // Read more unfolds the rest (and Show less folds it).
                AnimatedSize(
                  duration: RiffDurations.select,
                  curve: RiffDurations.selectCurve,
                  alignment: Alignment.topCenter,
                  child: Text(
                    d.description,
                    maxLines: _expanded ? null : 4,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
                    decoration: ShapeDecoration(
                      shape: StadiumBorder(
                          side: BorderSide(
                              color: Theme.of(context).dividerColor, width: 0)),
                    ),
                    // Centred up and down only: the chip hugs its label.
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        s[0].toUpperCase() + s.substring(1),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface),
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
                                ? const Align(
                                    alignment: Alignment.centerLeft,
                                    child: NowPlayingBars())
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

          if (player == null) return _loadedFade.row(row(false));
          return _loadedFade
              .row(Obx(() => row(player.currentSong.value?.id == id)));
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
