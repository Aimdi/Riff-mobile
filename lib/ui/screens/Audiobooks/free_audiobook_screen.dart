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
import '../Home/home_layout.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_book_page.dart';
import 'audiobook_download_button.dart';
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
                  child: _loadedFade.row(AudiobookAbout(
                      description: _detail!.description,
                      subjects: _detail!.subjects))),
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
    final d = _detail;
    final last = AudiobookProgressService.lastTrackForBook(book.id);
    final lastIdx = (last?['trackIndex'] as num?)?.toInt();
    return AudiobookBookHeader(
      cover: AudiobookDownloads.coverOf(book.id) ?? book.cover,
      title: book.title,
      author: book.author,
      lines: [
        if (d != null)
          episodeMetaLine([
            audiobookChapterCount(d.chapters.length),
            compactEpisodeLength(d.totalSec.round()),
            d.language,
          ]),
      ],
      playLabel: lastIdx != null && d != null
          ? '${'resume'.tr} · ${'chapterOf'.trParams({
                  'n': '${lastIdx + 1}',
                  'total': '${d.chapters.length}'
                })}'
          : 'play'.tr,
      onPlay: d == null || d.chapters.isEmpty ? null : () => _play(),
    );
  }

  Widget _chapters(BuildContext context, FreeAudiobookDetail d) {
    final player = Get.isRegistered<PlayerController>()
        ? Get.find<PlayerController>()
        : null;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final c = d.chapters[i];
          final id = '$freeAudiobookIdPrefix${d.book.id}_${c.index}';
          Widget row(bool playing) => AudiobookChapterRow(
                number: i + 1,
                title: c.title,
                durationSec: c.durationSec.round(),
                playing: playing,
                progress: AudiobookProgressService.progress(id),
                onTap: () => _play(index: i),
              );

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
