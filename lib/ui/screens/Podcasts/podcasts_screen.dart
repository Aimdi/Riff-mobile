import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/podcast_play.dart';
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
          memCacheWidth:
              (52 * MediaQuery.devicePixelRatioOf(context)).round(),
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => const Icon(Icons.podcasts, size: 40),
        ),
      ),
      title: Text(p['title'] ?? '', maxLines: 1),
      subtitle: Text(p['author'] ?? '', maxLines: 1),
      trailing: PodcastFollowButton(
        compact: true,
        following: subscribed,
        onPressed: () async {
          if (subscribed) {
            await PodcastService.unsubscribe(p['feedUrl']);
          } else {
            await PodcastService.subscribe(p);
          }
          setState(() {});
        },
      ),
      onTap: () async {
        if (shouldPlayPodcastShowOnTap()) {
          final ok = await playPodcastShow(p);
          if (ok) return;
        }
        Get.to(() => PodcastEpisodesScreen(podcast: p));
      },
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

  /// Lean MediaItem for the long-press sheet — skips HQ thumb work so the
  /// sheet can open immediately. Still carries description / feedUrl for
  /// shownotes + open-show actions.
  MediaItem _toSheetItem(Map<String, dynamic> e) => MediaItem(
        id: e['id'],
        title: e['title'] ?? '',
        artist: widget.podcast['title'],
        duration: () {
          final sec = e['durationSec'];
          final n = sec is int ? sec : int.tryParse('$sec') ?? 0;
          return n > 0 ? Duration(seconds: n) : null;
        }(),
        artUri: Uri.tryParse(
          (e['artwork'] ?? widget.podcast['artwork'] ?? '').toString(),
        ),
        extras: {
          'url': e['url'],
          'isPodcast': true,
          'description': e['description'],
          'date': e['date'],
          'pubDateMs': e['pubDateMs'] ?? 0,
          'feedUrl': widget.podcast['feedUrl'],
          if (e['chaptersUrl'] != null) 'chaptersUrl': e['chaptersUrl'],
          if (e['transcriptUrl'] != null) 'transcriptUrl': e['transcriptUrl'],
          if (e['transcriptUrl'] != null)
            'transcriptType': e['transcriptType'],
        },
      );

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
          'date': e['date'],
          'pubDateMs': e['pubDateMs'] ?? 0,
          'feedUrl': widget.podcast['feedUrl'],
          if (e['chaptersUrl'] != null) 'chaptersUrl': e['chaptersUrl'],
          if (e['transcriptUrl'] != null) 'transcriptUrl': e['transcriptUrl'],
          if (e['transcriptUrl'] != null)
            'transcriptType': e['transcriptType'],
        },
      );

  Future<void> _playFrom(int index) async {
    final items = _episodes.map(_toMediaItem).toList();
    final ok =
        await Get.find<PlayerController>().playPlayListSong(items, index);
    if (!ok) snackOperationFailed();
  }

  Future<void> _toggleSubscribe() async {
    final feed = widget.podcast['feedUrl'] ?? '';
    if (PodcastService.isSubscribed(feed)) {
      await PodcastService.unsubscribe(feed);
    } else {
      await PodcastService.subscribe(widget.podcast);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.podcast['title'] ?? '', maxLines: 1),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed header — cover art + title + Follow stay pinned while
                // the episode list scrolls.
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
    final theme = Theme.of(context);
    final art = (widget.podcast['artwork'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: art,
              width: 96,
              height: 96,
              memCacheWidth:
                  (96 * MediaQuery.devicePixelRatioOf(context)).round(),
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
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if ((widget.podcast['author'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.podcast['author'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_episodes.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => _playFrom(0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text('play'.tr),
                      ),
                    Obx(() {
                      PodcastService.subsRev.value;
                      final subscribed = PodcastService.isSubscribed(
                          widget.podcast['feedUrl'] ?? '');
                      return PodcastFollowButton(
                        following: subscribed,
                        onPressed: _toggleSubscribe,
                      );
                    }),
                  ],
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
    final id = '${e['id']}';
    final date = (e['date'] ?? '').toString();
    final size = PodcastService.formatSize(e['sizeBytes'] ?? 0);
    final totSec = (e['durationSec'] is int)
        ? e['durationSec'] as int
        : int.tryParse('${e['durationSec']}') ?? 0;
    final left = PodcastProgressService.remainingSec(id,
        fallbackDurationSec: totSec);
    String timeLabel = '';
    if (left != null && left > 0) {
      final fmt = PodcastService.formatDuration(left);
      final inProgress = PodcastProgressService.progress(id) != null;
      timeLabel = inProgress && left < totSec
          ? '$fmt ${'left'.tr}'
          : PodcastService.formatDuration(totSec);
    } else {
      timeLabel = PodcastService.formatDuration(totSec);
    }
    final prog = PodcastProgressService.progress(id);
    final meta = [date, size].where((s) => s.isNotEmpty).join('  ·  ');
    final art =
        (e['artwork'] ?? widget.podcast['artwork'] ?? '').toString();
    return InkWell(
      onTap: () => _playFrom(i),
      onLongPress: () => showAddToQueueSheet(context, _toSheetItem(e)),
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
                      memCacheWidth:
                          (56 * MediaQuery.devicePixelRatioOf(context))
                              .round(),
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
