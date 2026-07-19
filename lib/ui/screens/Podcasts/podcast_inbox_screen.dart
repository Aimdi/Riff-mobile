import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/music_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import 'podcasts_library_controller.dart';

/// AntennaPod-style Inbox: the latest episodes across every subscribed podcast,
/// merged into one list. Episodes are fetched per subscription and interleaved
/// newest-first (round-robin) so recent episodes from each show surface at the
/// top. Tap an episode to play it.
class PodcastInboxScreen extends StatefulWidget {
  const PodcastInboxScreen({super.key});

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
    final subs = Get.find<LibraryPodcastsController>().libraryPodcasts.toList();
    if (subs.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final ms = Get.find<MusicServices>();
    final lists = await Future.wait(subs.take(25).map((p) async {
      try {
        final data = await ms.getPodcast(p.playlistId, limit: 15);
        return List<MediaItem>.from(data['tracks'] ?? const []);
      } catch (_) {
        return <MediaItem>[];
      }
    }));
    final merged = _roundRobin(lists.where((l) => l.isNotEmpty).toList());
    if (mounted) {
      setState(() {
        _episodes = merged;
        _loading = false;
      });
    }
  }

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
    return Scaffold(
      appBar: AppBar(title: Text("podcastInbox".tr)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _episodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "noInboxEpisodes".tr,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _loading = true);
                    await _load();
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 200),
                    itemCount: _episodes.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 12),
                    itemBuilder: (_, i) => _row(context, i),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(width: 8),
            const Icon(Icons.play_circle_outline, size: 30),
          ],
        ),
      ),
    );
  }
}
