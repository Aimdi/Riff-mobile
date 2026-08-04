import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import 'podcast_empty_state.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PodcastInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshNonce != widget.refreshNonce) {
      setState(() => _loading = true);
      _load();
    }
  }

  Future<void> _load() async {
    // Two subscription sources: YouTube-Music library shows and iTunes/RSS
    // subscriptions (from Discover / categories). Merge both into the inbox.
    final ytSubs =
        Get.find<LibraryPodcastsController>().libraryPodcasts.toList();
    final rssSubs = PodcastService.subscriptions;
    if (ytSubs.isEmpty && rssSubs.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final ms = Get.find<MusicServices>();
    final ytFutures = ytSubs.take(25).map((p) async {
      try {
        if (p.kind == 'yt_channel' ||
            RegExp(r'^UC[\w-]{20,}$').hasMatch(p.playlistId)) {
          final data =
              await ms.getChannelAsPodcast(p.playlistId, limit: 15);
          return List<MediaItem>.from(data['tracks'] ?? const []);
        }
        final data = await ms.getPodcast(p.playlistId, limit: 15);
        return List<MediaItem>.from(data['tracks'] ?? const []);
      } catch (_) {
        return <MediaItem>[];
      }
    });
    final rssFutures = rssSubs.take(25).map((s) async {
      try {
        final feedUrl = '${s['feedUrl']}';
        final eps = await PodcastService.episodes(
          feedUrl,
          '${s['title'] ?? ''}',
          '${s['artwork'] ?? ''}',
        );
        return eps
            .take(12)
            .map((e) => _rssToMediaItem(e, '${s['title'] ?? ''}', feedUrl))
            .toList();
      } catch (_) {
        return <MediaItem>[];
      }
    });
    final lists = await Future.wait([...ytFutures, ...rssFutures]);
    final merged =
        _mergeNewestFirst(lists.where((l) => l.isNotEmpty).toList());
    if (mounted) {
      setState(() {
        _episodes = merged;
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
        artUri: Uri.tryParse(
            Thumbnail((e['artwork'] ?? '').toString()).extraHigh),
        extras: {
          'url': e['url'],
          'isPodcast': true,
          'description': e['description'],
          'date': e['date'],
          'pubDateMs': e['pubDateMs'] ?? 0,
          'feedUrl': feedUrl,
          if (e['chaptersUrl'] != null) 'chaptersUrl': e['chaptersUrl'],
          if (e['transcriptUrl'] != null) 'transcriptUrl': e['transcriptUrl'],
          if (e['transcriptUrl'] != null)
            'transcriptType': e['transcriptType'],
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

  void _play(int index) {
    Get.find<PlayerController>().playPlayListSong(_episodes, index);
  }

  /// Resume an in-progress episode and queue the rest of that show (or the
  /// inbox from that point) so continuous playback doesn't stop after one.
  void _playContinue(MediaItem item) {
    final pc = Get.find<PlayerController>();
    final show = (item.artist ?? '').trim();

    if (show.isNotEmpty) {
      final same =
          _episodes.where((e) => (e.artist ?? '').trim() == show).toList();
      final i = same.indexWhere((e) => e.id == item.id);
      if (i >= 0) {
        pc.playPlayListSong(same, i);
        return;
      }
      if (same.isNotEmpty) {
        pc.playPlayListSong(
            [item, ...same.where((e) => e.id != item.id)], 0);
        return;
      }
    }

    final idx = _episodes.indexWhere((e) => e.id == item.id);
    pc.playPlayListSong(idx >= 0 ? _episodes : [item], idx >= 0 ? idx : 0);
  }

  String _remainingLabel(MediaItem e) {
    final left = PodcastProgressService.remainingSec(
      e.id,
      fallbackDurationSec: e.duration?.inSeconds,
    );
    if (left == null || left <= 0) {
      return PodcastService.formatDuration(e.duration?.inSeconds ?? 0);
    }
    final tot = e.duration?.inSeconds ?? 0;
    if (tot > 0 && left >= tot) {
      return PodcastService.formatDuration(tot);
    }
    final fmt = PodcastService.formatDuration(left);
    return fmt.isEmpty ? '' : '$fmt ${'left'.tr}';
  }

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text("podcastInbox".tr)),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final continueItems = PodcastProgressService.inProgress();
    final empty = _episodes.isEmpty && continueItems.isEmpty;
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 200),
        children: [
          if (continueItems.isNotEmpty) ...[
            _sectionHeader(context, "continueListening".tr),
            ...continueItems
                .take(8)
                .map((r) => _continueRow(context, r)),
            const SizedBox(height: 8),
          ],
          if (_episodes.isNotEmpty) ...[
            _sectionHeader(context, "latestEpisodes".tr),
            for (int i = 0; i < _episodes.length; i++) ...[
              _row(context, i),
              if (i != _episodes.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 12),
            ],
          ],
          if (empty) _emptyState(context),
        ],
      ),
    );
  }

  /// Friendly empty state pointing at the Discover tab instead of a bare
  /// text line floating in a blank screen (shared layout across tabs).
  Widget _emptyState(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: PodcastEmptyState(
        icon: Icons.podcasts,
        message: "noInboxEpisodes".tr,
        actionLabel: widget.onDiscover != null ? 'discover'.tr : null,
        onAction: widget.onDiscover,
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)),
    );
  }

  /// "Continue" row (mockup style): rounded art with a green play button, title,
  /// show name and a green progress bar. Tapping resumes from the saved spot.
  Widget _continueRow(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final item = PodcastProgressService.toMediaItem(r);
    final art = Thumbnail(item.artUri?.toString() ?? '').medium;
    final prog = PodcastProgressService.progress(item.id) ?? 0.0;
    return InkWell(
      onTap: () => _playContinue(item),
      onLongPress: () => showAddToQueueSheet(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: art,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.podcasts, size: 44),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow,
                          size: 22, color: theme.colorScheme.onSecondary),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if ((item.artist ?? '').trim().isNotEmpty)
                        Text(item.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      if (_remainingLabel(item).isNotEmpty)
                        Text(_remainingLabel(item),
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: prog,
                minHeight: 4,
                backgroundColor:
                    theme.colorScheme.onSurface.withOpacity(0.15),
                valueColor:
                    AlwaysStoppedAnimation(theme.colorScheme.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final e = _episodes[i];
    final date = (e.extras?['date'] ?? '').toString().trim();
    final show = e.artist ?? '';
    final meta = [date, show].where((s) => s.isNotEmpty).join('  ·  ');
    final timeLabel = _remainingLabel(e);
    final prog = PodcastProgressService.progress(e.id);
    final art = Thumbnail(e.artUri?.toString() ?? '').medium;
    return InkWell(
      onTap: () => _play(i),
      onLongPress: () => showAddToQueueSheet(context, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: art,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.podcasts, size: 40),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        Text(
                          e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (timeLabel.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              timeLabel,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        if (prog != null && prog > 0 && prog < 1) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: prog,
                              minHeight: 3,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation(
                                  Theme.of(context).colorScheme.secondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.play_circle_outline, size: 30),
          ],
        ),
      ),
    );
  }
}
