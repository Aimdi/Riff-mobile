import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import 'podcast_queue_screen.dart';

/// AntennaPod-style podcast section: discover via Apple's directory,
/// subscribe locally (nothing reported anywhere), play episodes straight
/// from their RSS enclosure URLs through Riff's normal audio pipeline.
class PodcastsScreen extends StatefulWidget {
  const PodcastsScreen({super.key});

  @override
  State<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends State<PodcastsScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _searchCtrl.text.trim();
    if (term.isEmpty) return;
    setState(() => _loading = true);
    final res = await PodcastService.search(term);
    setState(() {
      _results = res;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final subs = PodcastService.subscriptions;
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 70),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("podcasts".tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: "searchPodcasts".tr,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward), onPressed: _search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _searched
                      ? _resultsList(_results, subscribeMode: true)
                      : _subscriptionsView(subs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionsView(List<Map<String, dynamic>> subs) {
    if (subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text("noSubscriptions".tr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    return ListView(
      children: [
        Text("mySubscriptions".tr,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...subs.map((p) => _podcastTile(p, subscribeMode: false)),
      ],
    );
  }

  Widget _resultsList(List<Map<String, dynamic>> items,
      {required bool subscribeMode}) {
    if (items.isEmpty) {
      return Center(
        child:
            Text("noResults".tr, style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => _podcastTile(items[i], subscribeMode: true),
    );
  }

  Widget _podcastTile(Map<String, dynamic> p, {required bool subscribeMode}) {
    final subscribed = PodcastService.isSubscribed(p['feedUrl'] ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: p['artwork'] ?? '',
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.podcasts, size: 40),
        ),
      ),
      title: Text(p['title'] ?? '', maxLines: 1),
      subtitle: Text(p['author'] ?? '', maxLines: 1),
      trailing: IconButton(
        icon: Icon(subscribed ? Icons.check_circle : Icons.add_circle_outline,
            color: subscribed ? Theme.of(context).colorScheme.secondary : null),
        onPressed: () async {
          if (subscribed) {
            await PodcastService.unsubscribe(p['feedUrl']);
          } else {
            await PodcastService.subscribe(p);
          }
          setState(() {});
        },
      ),
      onTap: () => Get.to(() => PodcastEpisodesScreen(podcast: p)),
    );
  }
}

/// Episode list for one podcast; tap an episode to play it.
class PodcastEpisodesScreen extends StatefulWidget {
  const PodcastEpisodesScreen({super.key, required this.podcast});
  final Map<String, dynamic> podcast;

  @override
  State<PodcastEpisodesScreen> createState() => _PodcastEpisodesScreenState();
}

class _PodcastEpisodesScreenState extends State<PodcastEpisodesScreen> {
  List<Map<String, dynamic>> _episodes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final eps = await PodcastService.episodes(widget.podcast['feedUrl'],
        widget.podcast['title'] ?? '', widget.podcast['artwork'] ?? '');
    if (mounted) {
      setState(() {
        _episodes = eps;
        _loading = false;
      });
    }
  }

  MediaItem _toMediaItem(Map<String, dynamic> e) => MediaItem(
        id: e['id'],
        title: e['title'],
        artist: widget.podcast['title'],
        duration: e['durationSec'] != null && e['durationSec'] > 0
            ? Duration(seconds: e['durationSec'])
            : null,
        artUri: Uri.tryParse(
          Thumbnail(
            (e['artwork'] ?? widget.podcast['artwork'] ?? '').toString(),
          ).extraHigh,
        ),
        extras: {
          'url': e['url'],
          'isPodcast': true,
          'description': e['description'],
          'date': DateTime.now().millisecondsSinceEpoch,
        },
      );

  void _playFrom(int index) {
    final items = _episodes.map(_toMediaItem).toList();
    Get.find<PlayerController>().playPlayListSong(items, index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.podcast['title'] ?? '', maxLines: 1)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed header — cover art + title + author stay pinned while
                // the episode list scrolls (AntennaPod layout).
                _header(context),
                const Divider(height: 1),
                Expanded(
                  child: _episodes.isEmpty
                      ? Center(child: Text("noEpisodes".tr))
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 200),
                          itemCount: _episodes.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, i) => _episodeRow(context, i),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _header(BuildContext context) {
    final art =
        (widget.podcast['artwork'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: art,
              width: 92,
              height: 92,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.podcasts, size: 60),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.podcast['title'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.podcast['author'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow(BuildContext context, int i) {
    final e = _episodes[i];
    final date = (e['date'] ?? '').toString();
    final size = PodcastService.formatSize(e['sizeBytes'] ?? 0);
    final duration = PodcastService.formatDuration(e['durationSec'] ?? 0);
    final meta = [date, size].where((s) => s.isNotEmpty).join('  ·  ');
    final art =
        (e['artwork'] ?? widget.podcast['artwork'] ?? '').toString();
    return InkWell(
      onTap: () => _playFrom(i),
      onLongPress: () => showAddToQueueSheet(context, _toMediaItem(e)),
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
                          e['title'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (duration.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              duration,
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
