import '../Home/home_layout.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';

import '/services/podcast_playback_profile.dart';

import '/models/thumbnail.dart';
import '/services/discovery/discovery_types.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import 'podcast_queue_screen.dart';
import 'podcast_show_view.dart';

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
      body: Column(children: [
        RiffPageHeader("podcasts".tr),
        Expanded(
            child: Padding(
          padding: const EdgeInsets.only(
              left: RiffSpacing.lg, top: RiffSpacing.sm, right: RiffSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: "searchPodcasts".tr,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const SongListShimmer(itemCount: 8, topPadding: 8)
                    : _searched
                        ? _resultsList(_results, subscribeMode: true)
                        : _subscriptionsView(subs),
              ),
            ],
          ),
        )),
      ]),
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
          memCacheWidth: (52 * MediaQuery.devicePixelRatioOf(context)).round(),
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
        _items = null;
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
          if (e['transcriptUrl'] != null) 'transcriptType': e['transcriptType'],
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
          if (e['transcriptUrl'] != null) 'transcriptType': e['transcriptType'],
        },
      );

  Future<void> _playFrom(int index) async {
    final items = _mediaItems;
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(items, index, source: DiscoverySource.podcast);
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

  List<MediaItem>? _items;

  List<MediaItem> get _mediaItems =>
      _items ??= _episodes.map(_toMediaItem).toList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      PodcastService.subsRev.value;
      final feed = (widget.podcast['feedUrl'] ?? '').toString();
      return PodcastShowView(
        playbackKey:
            podcastShowKeyForFeed(widget.podcast['feedUrl']?.toString()),
        title: (widget.podcast['title'] ?? '').toString(),
        author: (widget.podcast['author'] ?? '').toString(),
        artUrl: (widget.podcast['artwork'] ?? '').toString(),
        description: (widget.podcast['description'] ?? '').toString(),
        episodes: _loading ? const [] : _mediaItems,
        loading: _loading,
        subscribed: PodcastService.isSubscribed(feed),
        onToggleSubscribe: _toggleSubscribe,
        onPlay: _playFrom,
        onEpisodeLongPress: (m) {
          final i = _mediaItems.indexWhere((e) => e.id == m.id);
          if (i >= 0) showAddToQueueSheet(context, _toSheetItem(_episodes[i]));
        },
      );
    });
  }
}
