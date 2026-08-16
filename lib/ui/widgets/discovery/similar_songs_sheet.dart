import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/discovery/discovery_service.dart';
import '../../player/player_controller.dart';
import '../snackbar.dart';
import '../song_list_tile.dart';

/// Bottom sheet listing ~25 similar tracks with an "unheard only" chip.
class SimilarSongsSheet extends StatefulWidget {
  const SimilarSongsSheet({super.key, required this.seed});
  final MediaItem seed;

  @override
  State<SimilarSongsSheet> createState() => _SimilarSongsSheetState();
}

class _SimilarSongsSheetState extends State<SimilarSongsSheet> {
  bool unheardOnly = false;
  bool loading = true;
  List<MediaItem> songs = [];

  @override
  void initState() {
    super.initState();
    unheardOnly = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>().unheardOnlyDefault
        : false;
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      if (!Get.isRegistered<DiscoveryService>()) {
        songs = [];
      } else {
        songs = await Get.find<DiscoveryService>()
            .similarSongs(widget.seed, limit: 25, unheardOnly: unheardOnly);
      }
    } catch (_) {
      songs = [];
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.7;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("similarSongs".tr,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        widget.seed.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  label: Text("unheardOnly".tr),
                  selected: unheardOnly,
                  onSelected: (v) {
                    setState(() => unheardOnly = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : songs.isEmpty
                    ? Center(child: Text("noSimilarSongs".tr))
                    : ListView.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, i) {
                          final song = songs[i];
                          return SongListTile(
                            song: song,
                            onTap: () async {
                              if (!Get.isRegistered<PlayerController>()) {
                                return;
                              }
                              final ok = await Get.find<PlayerController>()
                                  .playPlayListSong(songs, i);
                              if (!context.mounted) return;
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                snackOperationFailed(context);
                              }
                            },
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () async {
                              final ok = await Get.find<PlayerController>()
                                  .enqueueSongList(songs);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  snackbar(
                                      context,
                                      ok
                                          ? "songEnqueueAlert".tr
                                          : "operationFailed".tr,
                                      size: SanckBarSize.MEDIUM));
                            },
                      icon: const Icon(Icons.queue_music),
                      label: Text("enqueueSong".tr),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () async {
                              final ok = await Get.find<PlayerController>()
                                  .playPlayListSong(songs, 0);
                              if (!context.mounted) return;
                              if (ok) {
                                Navigator.pop(context);
                              } else {
                                snackOperationFailed(context);
                              }
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: Text("playAll".tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
