import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_bookmarks.dart';
import '/services/podcast_download_service.dart';
import '/services/podcast_library.dart';
import '/services/podcast_playback_profile.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_empty_state.dart';
import 'podcast_layout.dart';
import 'podcast_queue_controller.dart';
import 'podcast_queue_screen.dart';
import 'podcasts_library_controller.dart';

/// AntennaPod-style Inbox: the latest episodes across every subscribed podcast,
/// merged into one list sorted by publish date (newest first). Tap an episode
/// to play it; Continue Listening resumes and queues the rest of that show.
class PodcastInboxScreen extends StatefulWidget {
  const PodcastInboxScreen({
    super.key,
    this.embedded = false,
    this.onDiscover,
    this.refreshNonce = 0,
  });

  /// When true, render just the content (no Scaffold/AppBar) so it can be shown
  /// inline inside the Podcasts library screen.
  final bool embedded;

  /// Switches the parent to the Discover tab (shown on the empty state).
  final VoidCallback? onDiscover;

  /// Bumped by the parent refresh shortcut to reload inbox episodes.
  final int refreshNonce;

  @override
  State<PodcastInboxScreen> createState() => _PodcastInboxScreenState();
}

class _PodcastInboxScreenState extends State<PodcastInboxScreen> {
  List<MediaItem> _episodes = [];
  bool _loading = true;

  /// Library filter chip; null shows the normal Inbox.
  EpisodeFilter? _filter;

  @override
  void initState() {
    super.initState();
    // A fresh cached inbox renders on the first frame, without the shimmer.
    final cached = _freshCache();
    if (cached != null) {
      _episodes = _unplayed(cached);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant PodcastInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshNonce != widget.refreshNonce) {
      setState(() => _loading = true);
      _load(force: true);
    }
  }

  /// Feeds fetched at once; the rest queue behind them.
  static const _fetchConcurrency = 6;

  static String _subsKey(
          List<Playlist> ytSubs, List<Map<String, dynamic>> rssSubs) =>
      ([
        for (final p in ytSubs) 'yt:${p.playlistId}',
        for (final s in rssSubs) 'rss:${s['feedUrl']}',
      ]..sort())
          .join('|');

  /// The merged inbox kept by the library controller, when it is recent and
  /// built from the current subscriptions. Reused across tab switches (the
  /// widget is recreated each time) instead of refetching every feed.
  List<MediaItem>? _freshCache() {
    final lib = Get.find<LibraryPodcastsController>();
    return lib.freshInbox(
        _subsKey(lib.libraryPodcasts.toList(), PodcastService.subscriptions));
  }

  Future<void> _load({bool force = false}) async {
    // Two subscription sources: YouTube-Music library shows and iTunes/RSS
    // subscriptions (from Discover / categories). Merge both into the inbox.
    final lib = Get.find<LibraryPodcastsController>();
    final ytSubs = lib.libraryPodcasts.toList();
    final rssSubs = PodcastService.subscriptions;
    if (ytSubs.isEmpty && rssSubs.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final subsKey = _subsKey(ytSubs, rssSubs);
    final cached = force ? null : lib.freshInbox(subsKey);
    if (cached != null) {
      _show(cached);
      return;
    }
    final ms = Get.find<MusicServices>();
    Future<List<MediaItem>> fetchYt(Playlist p) async {
      try {
        if (p.kind == 'yt_channel' ||
            RegExp(r'^UC[\w-]{20,}$').hasMatch(p.playlistId)) {
          final data = await ms.getChannelAsPodcast(p.playlistId, limit: 15);
          return [
            for (final m in List<MediaItem>.from(data['tracks'] ?? const []))
              withPodcastShowId(m, p.playlistId)
          ];
        }
        final data = await ms.getPodcast(p.playlistId, limit: 15);
        return [
          for (final m in List<MediaItem>.from(data['tracks'] ?? const []))
            withPodcastShowId(m, p.playlistId)
        ];
      } catch (_) {
        return <MediaItem>[];
      }
    }

    Future<List<MediaItem>> fetchRss(Map<String, dynamic> s) async {
      try {
        final feedUrl = '${s['feedUrl']}';
        final eps = await PodcastService.episodes(
          feedUrl,
          '${s['title'] ?? ''}',
          '${s['artwork'] ?? ''}',
          maxItems: 12,
        );
        return eps
            .take(12)
            .map((e) => _rssToMediaItem(e, '${s['title'] ?? ''}', feedUrl))
            .toList();
      } catch (_) {
        return <MediaItem>[];
      }
    }

    final tasks = <Future<List<MediaItem>> Function()>[
      for (final p in ytSubs) () => fetchYt(p),
      for (final s in rssSubs) () => fetchRss(s),
    ];
    final lists =
        await mapWithConcurrency(tasks, _fetchConcurrency, (t) => t());
    final merged = _mergeNewestFirst(lists.where((l) => l.isNotEmpty).toList());
    lib.storeInbox(merged, subsKey);
    _show(merged);
  }

  // AntennaPod-style: hide finished episodes from Latest (still in Continue
  // until cleared; mark-unplayed brings them back). Each show's "Keep
  // latest" archives its older unplayed episodes here.
  List<MediaItem> _unplayed(List<MediaItem> merged) =>
      PodcastLibrary.applyKeepLatest(merged)
          .where((e) => !PodcastProgressService.isPlayed(e.id))
          .toList();

  /// With a chip on: every episode Riff knows about (Inbox, in progress,
  /// Up Next, downloads, bookmarks) that matches it.
  List<MediaItem> _filtered(EpisodeFilter f) {
    final bookmarks = PodcastBookmarkStore.all;
    final marked = {for (final b in bookmarks) b.episodeId};
    final all = uniqueEpisodes([
      _episodes,
      PodcastProgressService.inProgress()
          .map(PodcastProgressService.toMediaItem),
      Get.find<PodcastQueueController>().queue,
      PodcastDownloadService.downloadedItems(),
      [
        for (final b in bookmarks)
          if (mediaItemFromSnapshot(b.episode) case final m?) m
      ],
    ]);
    return [
      for (final e in all)
        if (matchesEpisodeFilter(
            f, PodcastLibrary.factsFor(e, bookmarked: marked)))
          e
    ];
  }

  void _show(List<MediaItem> merged) {
    final inbox = _unplayed(merged);
    if (mounted) {
      setState(() {
        _episodes = inbox;
        _loading = false;
      });
    }
  }

  MediaItem _rssToMediaItem(
          Map<String, dynamic> e, String podcastTitle, String feedUrl) =>
      MediaItem(
        id: '${e['id']}',
        title: '${e['title'] ?? ''}',
        artist: podcastTitle,
        duration: (e['durationSec'] != null && (e['durationSec'] as int) > 0)
            ? Duration(seconds: e['durationSec'] as int)
            : null,
        artUri:
            Uri.tryParse(Thumbnail((e['artwork'] ?? '').toString()).extraHigh),
        extras: {
          'url': e['url'],
          'isPodcast': true,
          'description': e['description'],
          'date': e['date'],
          'pubDateMs': e['pubDateMs'] ?? 0,
          'feedUrl': feedUrl,
          if (e['chaptersUrl'] != null) 'chaptersUrl': e['chaptersUrl'],
          if (e['transcriptUrl'] != null) 'transcriptUrl': e['transcriptUrl'],
          if (e['transcriptUrl'] != null) 'transcriptType': e['transcriptType'],
        },
      );

  /// Flatten per-podcast lists and sort by pubDateMs (newest first). Items
  /// without a parseable date (typical of YT shelves) sort after dated ones.
  List<MediaItem> _mergeNewestFirst(List<List<MediaItem>> lists) {
    final all = <MediaItem>[for (final l in lists) ...l];
    all.sort((a, b) {
      final am = (a.extras?['pubDateMs'] as int?) ?? 0;
      final bm = (b.extras?['pubDateMs'] as int?) ?? 0;
      if (am == 0 && bm == 0) {
        return (b.extras?['date'] ?? '')
            .toString()
            .compareTo((a.extras?['date'] ?? '').toString());
      }
      if (am == 0) return 1;
      if (bm == 0) return -1;
      return bm.compareTo(am);
    });
    return all;
  }

  Future<void> _play(List<MediaItem> list, int index) async {
    if (await openInWizeStreamIfPreferred(list[index])) return;
    final ok = await Get.find<PlayerController>().playPlayListSong(list, index);
    if (!ok) snackOperationFailed();
  }

  /// Resume an in-progress episode and queue the rest of that show (or the
  /// inbox from that point) so continuous playback doesn't stop after one.
  Future<void> _playContinue(MediaItem item) async {
    if (await openInWizeStreamIfPreferred(item)) return;
    final pc = Get.find<PlayerController>();
    final show = (item.artist ?? '').trim();

    if (show.isNotEmpty) {
      final same =
          _episodes.where((e) => (e.artist ?? '').trim() == show).toList();
      final i = same.indexWhere((e) => e.id == item.id);
      if (i >= 0) {
        final ok = await pc.playPlayListSong(same, i);
        if (!ok) snackOperationFailed();
        return;
      }
      if (same.isNotEmpty) {
        final ok = await pc
            .playPlayListSong([item, ...same.where((e) => e.id != item.id)], 0);
        if (!ok) snackOperationFailed();
        return;
      }
    }

    final idx = _episodes.indexWhere((e) => e.id == item.id);
    final ok = await pc.playPlayListSong(
        idx >= 0 ? _episodes : [item], idx >= 0 ? idx : 0);
    if (!ok) snackOperationFailed();
  }

  /// "25m left" while partly played, else the episode length ("45m").
  String _remainingLabel(MediaItem e) {
    final left = PodcastProgressService.remainingSec(
      e.id,
      fallbackDurationSec: e.duration?.inSeconds,
    );
    final tot = e.duration?.inSeconds ?? 0;
    if (left == null || left <= 0 || (tot > 0 && left >= tot)) {
      return compactEpisodeLength(tot);
    }
    final fmt = compactEpisodeLength(left);
    return fmt.isEmpty ? '' : '$fmt ${'left'.tr}';
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.embedded) return body;
    return Scaffold(
      body: Column(children: [
        RiffPageHeader("podcastInbox".tr),
        Expanded(child: body),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const SongListShimmer(itemCount: 8, topPadding: 8);
    }
    final filter = _filter;
    final list = filter == null ? _episodes : _filtered(filter);
    final continueItems = filter != null
        ? const <Map<String, dynamic>>[]
        : PodcastProgressService.inProgress().take(8).toList();
    final empty = list.isEmpty && continueItems.isEmpty;
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _load(force: true);
      },
      // Lazy slivers — avoid building hundreds of episode rows + images
      // up-front on every setState/refresh.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _chips(context)),
          if (continueItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: HomeSectionHeader("continueListening".tr, top: 12),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: PodcastContinueCard.heightFor(context),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
                  itemCount: continueItems.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: HomeLayout.cardGap),
                  itemBuilder: (context, i) => KeyedSubtree(
                    key: ValueKey('cont_${continueItems[i]['id']}'),
                    child: _continueCard(context, continueItems[i]),
                  ),
                ),
              ),
            ),
          ],
          if (list.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: HomeSectionHeader(
                  filter == null
                      ? "latestEpisodes".tr
                      : '${_filterLabel(filter)} · ${list.length}',
                  top: continueItems.isEmpty ? 12 : HomeLayout.sectionTop),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => KeyedSubtree(
                  key: ValueKey(list[i].id),
                  child: _row(context, list, i),
                ),
                childCount: list.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            ),
          ],
          if (empty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: filter == null
                  ? _emptyState(context)
                  : PodcastEmptyState(
                      icon: Icons.filter_list_off_rounded,
                      message: 'noFilteredEpisodes'.tr,
                      actionLabel: 'clearFilter'.tr,
                      actionIcon: Icons.close_rounded,
                      onAction: () => setState(() => _filter = null),
                    ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 200)),
        ],
      ),
    );
  }

  /// Friendly empty state pointing at the Discover tab instead of a bare
  /// text line floating in a blank screen (shared layout across tabs).
  Widget _emptyState(BuildContext context) {
    return PodcastEmptyState(
      icon: Icons.podcasts,
      message: "noInboxEpisodes".tr,
      actionLabel: widget.onDiscover != null ? 'discover'.tr : null,
      onAction: widget.onDiscover,
    );
  }

  /// Continue-listening card: resumes from the saved spot and queues the
  /// rest of that show.
  Widget _continueCard(BuildContext context, Map<String, dynamic> r) {
    final item = PodcastProgressService.toMediaItem(r);
    return PodcastContinueCard(
      artUrl: Thumbnail(item.artUri?.toString() ?? '').medium,
      title: item.title,
      show: item.artist ?? '',
      progress: PodcastProgressService.progress(item.id) ?? 0.0,
      timeLeft: _remainingLabel(item),
      onTap: () => _playContinue(item),
      onLongPress: () => showAddToQueueSheet(context, item),
    );
  }

  static String _filterLabel(EpisodeFilter f) => 'episodeFilter_${f.name}'.tr;

  /// New · In progress · Queued · Downloaded · Bookmarked · Short. One at a
  /// time; tap the selected one again to go back to the Inbox.
  Widget _chips(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            HomeLayout.gutter, 8, HomeLayout.gutter, 2),
        itemCount: EpisodeFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = EpisodeFilter.values[i];
          final on = _filter == f;
          return _FilterPill(
            label: _filterLabel(f),
            selected: on,
            onTap: () => setState(() => _filter = on ? null : f),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, List<MediaItem> list, int i) {
    final e = list[i];
    return PodcastEpisodeTile(
      artUrl: Thumbnail(e.artUri?.toString() ?? '').medium,
      title: e.title,
      meta: episodeMetaLine(
          [e.artist, '${e.extras?['date'] ?? ''}', _remainingLabel(e)]),
      progress: PodcastProgressService.progress(e.id),
      onTap: () => _play(list, i),
      onLongPress: () =>
          showAddToQueueSheet(context, e, onChanged: () => setState(() {})),
    );
  }
}

/// Small outlined filter chip, quieter than the section tabs above it.
class _FilterPill extends StatelessWidget {
  const _FilterPill(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final fg = selected ? accent : (homeMutedColor(context) ?? Colors.grey);
    return Material(
      color: selected ? accent.withOpacity(0.14) : Colors.transparent,
      shape: StadiumBorder(
          side: BorderSide(
              color: selected ? accent : fg.withOpacity(0.45), width: 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 15, color: accent),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
