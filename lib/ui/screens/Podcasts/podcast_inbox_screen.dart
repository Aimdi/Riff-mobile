import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import 'podcast_queue_screen.dart';
import 'podcasts_library_controller.dart';

/// AntennaPod-style Inbox: the latest episodes across every subscribed podcast,
/// merged into one list. Episodes are fetched per subscription and interleaved
/// newest-first (round-robin) so recent episodes from each show surface at the
/// top. Tap an episode to play it.
class PodcastInboxScreen extends StatefulWidget {
  const PodcastInboxScreen({super.key, this.embedded = false, this.onDiscover});

  /// When true, render just the content (no Scaffold/AppBar) so it can be shown
  /// inline inside the Podcasts library screen.
  final bool embedded;

  /// Switches the parent to the Discover tab (shown on the empty state).
  final VoidCallback? onDiscover;

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
        final data = await ms.getPodcast(p.playlistId, limit: 15);
        return List<MediaItem>.from(data['tracks'] ?? const []);
      } catch (_) {
        return <MediaItem>[];
      }
    });
    final rssFutures = rssSubs.take(25).map((s) async {
      try {
        final eps = await PodcastService.episodes(
          '${s['feedUrl']}',
          '${s['title'] ?? ''}',
          '${s['artwork'] ?? ''}',
        );
        return eps
            .take(12)
            .map((e) => _rssToMediaItem(e, '${s['title'] ?? ''}'))
            .toList();
      } catch (_) {
        return <MediaItem>[];
      }
    });
    final lists = await Future.wait([...ytFutures, ...rssFutures]);
    final merged = _roundRobin(lists.where((l) => l.isNotEmpty).toList());
    if (mounted) {
      setState(() {
        _episodes = merged;
        _loading = false;
      });
    }
  }

  MediaItem _rssToMediaItem(Map<String, dynamic> e, String podcastTitle) =>
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
          if (e['chaptersUrl'] != null) 'chaptersUrl': e['chaptersUrl'],
          if (e['transcriptUrl'] != null) 'transcriptUrl': e['transcriptUrl'],
          if (e['transcriptUrl'] != null)
            'transcriptType': e['transcriptType'],
        },
      );

  /// Interleave per-podcast episode lists (each already newest-first) so the
  /// most recent episode of every show comes first, then the second, etc.
  List<MediaItem> _roundRobin(List<List<MediaItem>> lists) {
    final out = <MediaItem>[];
    var i = 0;
    var any = true;
    while (any) {
      any = false;
      for (final l in lists) {
        if (i < l.length) {
          out.add(l[i]);
          any = true;
        }
      }
      i++;
    }
    return out;
  }

  void _play(int index) {
    Get.find<PlayerController>().playPlayListSong(_episodes, index);
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
  /// text line floating in a blank screen.
  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      child: Column(
        children: [
          Icon(Icons.podcasts, size: 56, color: dim?.withOpacity(0.4)),
          const SizedBox(height: 14),
          Text(
            "noInboxEpisodes".tr,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: dim?.withOpacity(0.7)),
          ),
          if (widget.onDiscover != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onDiscover,
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text('discover'.tr),
            ),
          ],
        ],
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
      onTap: () =>
          Get.find<PlayerController>().playPlayListSong([item], 0),
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
    final durationText = PodcastService.formatDuration(e.duration?.inSeconds ?? 0);
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
                        if (durationText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              durationText,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
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
