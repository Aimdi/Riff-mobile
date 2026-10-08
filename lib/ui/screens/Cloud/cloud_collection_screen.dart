import '../Home/home_layout.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/cloud_music_service.dart';
import '/services/discovery/discovery_types.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/widgets/generated_cover.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/widgets/snackbar.dart';
import 'cloud_screen.dart';

/// An album or playlist from the self-hosted server, with playable tracks.
class CloudCollectionScreen extends StatefulWidget {
  const CloudCollectionScreen(
      {super.key,
      required this.collectionId,
      required this.isPlaylist,
      required this.title});
  final String collectionId;
  final bool isPlaylist;
  final String title;

  @override
  State<CloudCollectionScreen> createState() => _CloudCollectionScreenState();
}

class _CloudCollectionScreenState extends State<CloudCollectionScreen> {
  CloudCollection? _detail;
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
      final cloud = Get.find<CloudMusicService>();
      final d = widget.isPlaylist
          ? await cloud.fetchPlaylist(widget.collectionId)
          : await cloud.fetchAlbum(widget.collectionId);
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

  Future<void> _playAll({bool shuffle = false}) async {
    final d = _detail;
    if (d == null || d.songs.isEmpty) return;
    final cloud = Get.find<CloudMusicService>();
    final list = shuffle ? (d.songs.toList()..shuffle()) : d.songs;
    final ok = await Get.find<PlayerController>().playPlayListSong(
        cloud.toMediaItems(list), 0,
        source: DiscoverySource.cloud);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(children: [
        RiffPageHeader(_detail?.name ?? widget.title),
        Expanded(
            child: _loading
                ? const SongListShimmer(itemCount: 8, topPadding: 12)
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              TextButton(
                                  onPressed: _load, child: Text('retry'.tr)),
                            ],
                          ),
                        ),
                      )
                    : _buildBody(theme)),
      ]),
    );
  }

  /// No cover, or it failed: a playlist's generated cover, else the icon.
  Widget _missingCover(ThemeData theme, CloudCollection d) {
    if (widget.isPlaylist) {
      return GeneratedCover(
          seed: widget.collectionId, title: d.name, size: _coverSide);
    }
    return Container(
      width: _coverSide,
      height: _coverSide,
      color: theme.primaryColorLight,
      child: const Icon(Icons.album, size: 40),
    );
  }

  static const double _coverSide = 120;

  Widget _buildBody(ThemeData theme) {
    final d = _detail!;
    final cloud = Get.find<CloudMusicService>();
    final cover = cloud.coverUrl(d.coverArt, size: 600);
    return ListView(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
          top: RiffSpacing.sm,
          right: RiffSpacing.lg,
          bottom: RiffSpacing.listEnd),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: d.songs.isEmpty ? null : () => _playAll(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: cover.isEmpty
                    ? _missingCover(theme, d)
                    : CachedNetworkImage(
                        imageUrl: cover,
                        width: _coverSide,
                        height: _coverSide,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _missingCover(theme, d),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: theme.textTheme.titleLarge),
                  if (d.subtitle != null && d.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(d.subtitle!, style: theme.textTheme.titleSmall),
                  ],
                  const SizedBox(height: 2),
                  Text('${d.songs.length} ${'items'.tr}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: d.songs.isEmpty ? null : () => _playAll(),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('playAll'.tr),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'shuffle'.tr,
                        onPressed: d.songs.isEmpty
                            ? null
                            : () => _playAll(shuffle: true),
                        icon: const Icon(Icons.shuffle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...List.generate(
          d.songs.length,
          (i) => CloudSongTile(songs: d.songs, index: i),
        ),
      ],
    );
  }
}
