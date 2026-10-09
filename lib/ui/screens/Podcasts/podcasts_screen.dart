import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/thumbnail.dart';
import '/services/discovery/discovery_types.dart';
import '/services/podcast_playback_profile.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/snackbar.dart';
import 'podcast_queue_screen.dart';
import 'podcast_show_view.dart';

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
