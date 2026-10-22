import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/ban_service.dart';
import '/services/discovery/discovery_service.dart';
import '/ui/theme/riff_tokens.dart';
import '../../player/player_controller.dart';
import '../../widgets/image_widget.dart';
import '../../widgets/riff_motion.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/song_list_tile.dart' show RiffRowHairline;
import '../Home/home_metrics.dart';

/// Songs a playlist's recommendations show at once, as in Spotify.
const playlistRecommendationCount = 10;

/// Songs the recommendations are based on: the latest added first, then
/// others spread over the playlist. Each [round] (Refresh) starts one song
/// further back, so it brings other songs.
List<MediaItem> recommendationSeeds(List<MediaItem> songs,
    {int round = 0, int count = 3}) {
  final n = songs.length;
  final stride = math.max(1, n ~/ count);
  final seeds = <MediaItem>[];
  for (var i = 0; i < count && i < n; i++) {
    final song = songs[(n - 1 - round - i * stride) % n];
    if (!seeds.any((s) => s.id == song.id)) seeds.add(song);
  }
  return seeds;
}

/// Up to [limit] songs from [perSeed] (what each seed brought), taken in
/// turn so every seed counts, each once, leaving out the ids in [exclude]
/// and songs [blocked] keeps out ("Never play this").
List<MediaItem> pickPlaylistRecommendations(List<List<MediaItem>> perSeed,
    {required Set<String> exclude,
    int limit = playlistRecommendationCount,
    bool Function(MediaItem song)? blocked}) {
  final picked = <MediaItem>[];
  final seen = {...exclude};
  final longest = perSeed.fold(0, (m, list) => math.max(m, list.length));
  for (var i = 0; i < longest && picked.length < limit; i++) {
    for (final list in perSeed) {
      if (i >= list.length || picked.length >= limit) continue;
      final song = list[i];
      if (seen.add(song.id) && !(blocked?.call(song) ?? false)) {
        picked.add(song);
      }
    }
  }
  return picked;
}

/// Spotify's "Recommended songs" under your own playlists: songs like the
/// ones in it, each with + to add it. Refresh brings others; nothing shows
/// when there are none (offline).
class PlaylistRecommendations extends StatefulWidget {
  const PlaylistRecommendations({
    super.key,
    required this.songs,
    required this.playlistTitle,
    required this.onAdd,
    this.load,
  });

  /// The playlist's songs: what the recommendations are based on, and
  /// left out of them.
  final List<MediaItem> songs;
  final String playlistTitle;

  /// Adds a song to the playlist; false when it couldn't.
  final Future<bool> Function(MediaItem song) onAdd;

  /// Songs like a seed ([DiscoveryService.similarSongs] when null).
  final Future<List<MediaItem>> Function(MediaItem seed)? load;

  @override
  State<PlaylistRecommendations> createState() =>
      _PlaylistRecommendationsState();
}

class _PlaylistRecommendationsState extends State<PlaylistRecommendations> {
  List<MediaItem> _songs = const [];
  bool _loading = true;
  int _round = 0;

  /// Shown before: Refresh brings other songs.
  final _shown = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<MediaItem>> _similar(MediaItem seed) async {
    final load = widget.load;
    if (load != null) return load(seed);
    if (!Get.isRegistered<DiscoveryService>()) return const [];
    return Get.find<DiscoveryService>().similarSongs(seed, limit: 15);
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    final seeds = recommendationSeeds(widget.songs, round: _round++);
    final perSeed = await Future.wait([
      for (final seed in seeds)
        _similar(seed).catchError((Object _) => <MediaItem>[]),
    ]);
    if (!mounted) return;
    var picked = pickPlaylistRecommendations(perSeed,
        exclude: {for (final s in widget.songs) s.id, ..._shown},
        blocked: BanService.isMediaItemBlocked);
    if (picked.isEmpty && _shown.isNotEmpty) {
      // Nothing new: show the earlier ones again rather than nothing.
      _shown.clear();
      picked = pickPlaylistRecommendations(perSeed,
          exclude: {for (final s in widget.songs) s.id},
          blocked: BanService.isMediaItemBlocked);
    }
    _shown.addAll(picked.map((s) => s.id));
    setState(() {
      _songs = picked;
      _loading = false;
    });
  }

  Future<void> _add(MediaItem song) async {
    final target = undoSnackbarTarget(context);
    final ok = await widget.onAdd(song);
    if (!mounted) return;
    if (ok) setState(() => _songs = [..._songs]..remove(song));
    showUndoSnackbar(
        target,
        ok
            ? 'addedToThisPlaylist'.trParams({'name': widget.playlistTitle})
            : 'operationFailed'.tr);
  }

  Future<void> _play(MediaItem song) async {
    if (!Get.isRegistered<PlayerController>()) return;
    final ok = await Get.find<PlayerController>().pushSongToQueue(song);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _songs.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiffSectionHeader(
          'recommendedSongs'.tr,
          action: IconButton(
            tooltip: 'refreshRecommendations'.tr,
            color: muted,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: RiffSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          // Fresh suggestions fade in where the spinner was.
          RiffFadeIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final song in _songs)
                  _RecommendedSongRow(
                    song: song,
                    onTap: () => _play(song),
                    onAdd: () => _add(song),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A song row in the song-list style (§5.2), with + where the row menu
/// would be.
class _RecommendedSongRow extends StatelessWidget {
  const _RecommendedSongRow(
      {required this.song, required this.onTap, required this.onAdd});

  final MediaItem song;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.xs),
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiffSpacing.lg, vertical: RiffSpacing.md),
              child: Row(
                children: [
                  ImageWidget(
                    size: RiffComponentSizes.rowArt,
                    song: song,
                    borderRadius: RiffRadii.xs,
                  ),
                  const SizedBox(width: RiffSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: RiffSpacing.xxs),
                        Text(
                          song.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: RiffSpacing.sm),
                  IconButton(
                    tooltip: 'addToThisPlaylist'.tr,
                    color: muted,
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
          const RiffRowHairline(inset: RiffRowHairline.textInset),
        ],
      ),
    );
  }
}
