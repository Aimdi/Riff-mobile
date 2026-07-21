import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';

/// Horizontal "Similar" row under player controls — lazily loaded for current track.
class PlayerSimilarRow extends StatefulWidget {
  const PlayerSimilarRow({super.key});

  @override
  State<PlayerSimilarRow> createState() => _PlayerSimilarRowState();
}

class _PlayerSimilarRowState extends State<PlayerSimilarRow> {
  String? _loadedForId;
  List<MediaItem> _songs = [];
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<DiscoveryService>()) {
      return const SizedBox.shrink();
    }
    final player = Get.find<PlayerController>();
    return Obx(() {
      final song = player.currentSong.value;
      if (song == null) return const SizedBox.shrink();
      if (_loadedForId != song.id && !_loading) {
        _load(song);
      }
      if (_songs.isEmpty && !_loading) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
            child: Text(
              "similarSongs".tr,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(
            height: 72,
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _songs.length,
                    itemBuilder: (context, i) {
                      final s = _songs[i];
                      return InkWell(
                        onTap: () {
                          // Play the tapped song now, with the rest of the
                          // similar list queued after it.
                          final list = List<MediaItem>.from(_songs);
                          list[i] = DiscoveryService.withSource(
                              s, DiscoverySource.similar);
                          player.playPlayListSong(list, i);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: ImageWidget(song: s, size: 56),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 100,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    Text(s.artist ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  Future<void> _load(MediaItem song) async {
    _loading = true;
    _loadedForId = song.id;
    try {
      final list = await Get.find<DiscoveryService>()
          .similarSongs(song, limit: 12, unheardOnly: false);
      if (mounted && _loadedForId == song.id) {
        setState(() {
          _songs = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _songs = [];
          _loading = false;
        });
      }
    }
  }
}
