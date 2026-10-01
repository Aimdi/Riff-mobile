import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../snackbar.dart';

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
        // Never start network work synchronously during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final current = player.currentSong.value;
          if (current != null && _loadedForId != current.id && !_loading) {
            _load(current);
          }
        });
      }
      if (_songs.isEmpty && !_loading) return const SizedBox.shrink();
      final fg = Theme.of(context).textTheme.titleMedium?.color ?? Colors.white;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              "similarSongs".tr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg.withOpacity(0.66),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _loading && _songs.isEmpty
                  ? const Center(
                      key: ValueKey('similar-loading'),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Opacity(
                      key: ValueKey('similar-${_loadedForId ?? 'x'}'),
                      opacity: _loading ? 0.45 : 1,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _songs.length,
                        itemBuilder: (context, i) {
                          final s = _songs[i];
                          return InkWell(
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              final list = List<MediaItem>.from(_songs);
                              list[i] = DiscoveryService.withSource(
                                  s, DiscoverySource.similar);
                              final ok = await player.playPlayListSong(list, i);
                              if (!ok) snackOperationFailed();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: ImageWidget(song: s, size: 48),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 108,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(s.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              height: 1.25,
                                              fontWeight: FontWeight.w600,
                                              color: fg,
                                            )),
                                        const SizedBox(height: 2),
                                        Text(s.artist ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              height: 1.25,
                                              color: fg.withOpacity(0.62),
                                            )),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: "playNext".tr,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                    iconSize: 20,
                                    icon: Icon(Icons.playlist_play_rounded,
                                        color: fg.withOpacity(0.62)),
                                    onPressed: () async {
                                      HapticFeedback.selectionClick();
                                      final ok = await player.playNext(s);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(snackbar(
                                        context,
                                        ok
                                            ? "${"playnextMsg".tr} ${s.title}"
                                            : "operationFailed".tr,
                                        size: SanckBarSize.MEDIUM,
                                      ));
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _load(MediaItem song) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadedForId = song.id;
      _songs = [];
    });
    try {
      final list = await Get.find<DiscoveryService>()
          .similarSongs(song, limit: 12, unheardOnly: false)
          .timeout(const Duration(seconds: 16), onTimeout: () => []);
      if (mounted && _loadedForId == song.id) {
        setState(() {
          _songs = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _loadedForId == song.id) {
        setState(() {
          _songs = [];
          _loading = false;
        });
      }
    }
  }
}
