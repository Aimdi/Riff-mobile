import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/cloud_music_service.dart';
import '/ui/player/player_controller.dart';
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
    await Get.find<PlayerController>()
        .playPlayListSong(cloud.toMediaItems(list), 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.name ?? widget.title),
        backgroundColor: theme.canvasColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _load, child: Text('retry'.tr)),
                      ],
                    ),
                  ),
                )
              : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final d = _detail!;
    final cloud = Get.find<CloudMusicService>();
    final cover = cloud.coverUrl(d.coverArt, size: 600);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 200),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: cover.isEmpty
                  ? Container(
                      width: 120,
                      height: 120,
                      color: theme.primaryColorLight,
                      child: Icon(
                          widget.isPlaylist
                              ? Icons.library_music
                              : Icons.album,
                          size: 40),
                    )
                  : CachedNetworkImage(
                      imageUrl: cover,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 120,
                        height: 120,
                        color: theme.primaryColorLight,
                        child: Icon(
                            widget.isPlaylist
                                ? Icons.library_music
                                : Icons.album,
                            size: 40),
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
                        onPressed:
                            d.songs.isEmpty ? null : () => _playAll(),
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
