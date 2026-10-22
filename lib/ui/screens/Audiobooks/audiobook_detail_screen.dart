import '../Home/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/shimmer_widgets/skeleton_fade.dart';
import '/services/audiobook_downloads.dart';
import '/services/audiobook_progress_service.dart';
import '/services/audiobookshelf_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../Podcasts/podcast_layout.dart';
import 'audiobook_book_page.dart';
import 'audiobook_download_button.dart';
import 'audiobook_play.dart';
import 'audiobook_widgets.dart' show audiobookChapterCount;

/// A book on your Audiobookshelf server: the same page as a free book's
/// (cover, Play / Resume, about, chapters).
class AudiobookDetailScreen extends StatefulWidget {
  const AudiobookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  State<AudiobookDetailScreen> createState() => _AudiobookDetailScreenState();
}

class _AudiobookDetailScreenState extends State<AudiobookDetailScreen> {
  AbsBookDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Metadata only: openBook() starts a server play session, which Play
      // opens itself; calling it here orphaned one session per visit.
      final d = await Get.find<AudiobookshelfService>()
          .fetchBookDetail(widget.bookId);
      if (mounted) {
        setState(() {
          _detail = d;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Play from [index] (chapter tap), or resume when [index] is null
  /// (primary Play / Resume button).
  ///
  /// A locally stored position wins over the server's: it is the more recent
  /// truth on this device, since the server value lags by up to the sync
  /// interval. The ABS session position still covers a book that was listened
  /// to on another Audiobookshelf client.
  Future<void> _play({int? index}) async {
    if (_detail == null) return;
    await playAudiobook(bookId: widget.bookId, index: index);
    if (mounted) setState(() {});
  }

  /// The large title under the cover has scrolled out of view: the bar
  /// shows it instead.
  bool _scrolledPastTitle = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    // The title starts under the cover.
    final past =
        n.metrics.pixels > audiobookPageCover(context) + RiffSpacing.lg;
    if (past != _scrolledPastTitle) {
      setState(() => _scrolledPastTitle = past);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final abs = Get.find<AudiobookshelfService>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(children: [
        RiffPageHeader(
          _detail?.title ?? 'audiobooks'.tr,
          // The book's own large title is just below until scrolled away.
          titleVisible: _detail == null || _scrolledPastTitle,
          actions: [
            if (_detail != null)
              AudiobookDownloadButton(
                bookId: widget.bookId,
                chapters: () => abs.toMediaItems(_detail!),
              ),
          ],
        ),
        Expanded(
            // What loaded fades in where the skeleton was.
            child: SkeletonFadeIn(
                skeleton: const SongListShimmer(itemCount: 8, topPadding: 12),
                child: _loading
                    ? null
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(RiffSpacing.xxl),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off_outlined,
                                      size: RiffComponentSizes.rowArt,
                                      color: theme.colorScheme.error),
                                  const SizedBox(height: RiffSpacing.md),
                                  Text(_error!,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyLarge),
                                  const SizedBox(height: RiffSpacing.md),
                                  TextButton(
                                      onPressed: _load,
                                      child: Text('retry'.tr)),
                                ],
                              ),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: _onScroll,
                            child: _buildBody(theme, abs)))),
      ]),
    );
  }

  Widget _buildBody(ThemeData theme, AudiobookshelfService abs) {
    final d = _detail!;
    final player = Get.isRegistered<PlayerController>()
        ? Get.find<PlayerController>()
        : null;
    final total = d.tracks
        .fold<double>(0, (sum, t) => sum + (t.duration > 0 ? t.duration : 0));
    // Where Play picks up, as the free book's page says it.
    final started = AudiobookProgressService.lastTrackForBook(d.id) != null ||
        d.currentTime > 5;
    final resumeAt = d.tracks.isEmpty
        ? 0
        : absResumePoint(d).$1.clamp(0, d.tracks.length - 1);
    final description = d.description ?? '';
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: RiffSpacing.sm),
            child: AudiobookBookHeader(
              // Downloaded, the cover kept on the phone.
              cover: AudiobookDownloads.coverOf(d.id) ??
                  abs.coverUrl(d.id, width: 600),
              title: d.title,
              author: d.author,
              lines: [
                if (d.narrator != null && d.narrator!.isNotEmpty)
                  '${'narrator'.tr}: ${d.narrator}',
                episodeMetaLine([
                  if (d.tracks.isNotEmpty)
                    audiobookChapterCount(d.tracks.length),
                  compactEpisodeLength(total.round()),
                ]),
              ],
              playLabel: started && d.tracks.isNotEmpty
                  ? '${'resume'.tr} · ${'chapterOf'.trParams({
                          'n': '${resumeAt + 1}',
                          'total': '${d.tracks.length}'
                        })}'
                  : 'play'.tr,
              onPlay: d.tracks.isEmpty ? null : () => _play(),
            ),
          ),
        ),
        if (description.isNotEmpty)
          SliverToBoxAdapter(child: AudiobookAbout(description: description)),
        SliverToBoxAdapter(child: HomeSectionHeader('chapters'.tr)),
        if (d.tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: HomeLayout.gutter, vertical: RiffSpacing.xxl),
              child: Text('absNoBooks'.tr, style: theme.textTheme.bodyMedium),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final t = d.tracks[i];
                final id = AudiobookshelfService.trackMediaId(d.id, t.index);
                Widget row(bool playing) => AudiobookChapterRow(
                      number: i + 1,
                      title: t.title,
                      durationSec: t.duration.round(),
                      playing: playing,
                      progress: AudiobookProgressService.progress(id),
                      onTap: () => _play(index: i),
                    );
                if (player == null) return row(false);
                return Obx(() => row(player.currentSong.value?.id == id));
              },
              childCount: d.tracks.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: RiffSpacing.listEnd)),
      ],
    );
  }
}
