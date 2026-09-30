import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_score.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../navigator.dart';
import '../../player/play_queue_order.dart';
import '../../player/player_controller.dart';
import '../../screens/Home/home_layout.dart';
import '../../utils/sheet_insets.dart';
import '../image_widget.dart';
import '../snackbar.dart';
import 'similar_songs_sheet.dart';

/// Horizontal carousel for a personal discovery section on Home.
class HomeDiscoverySection extends StatelessWidget {
  const HomeDiscoverySection({super.key, required this.section, this.badge});
  final DiscoverySection section;

  /// Optional pill next to the title (e.g. "Updated" after regeneration).
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final tracks =
        section.tracks.map((m) => MediaItemBuilder.fromJson(m)).toList();
    if (tracks.isEmpty) return const SizedBox.shrink();

    final isDailyMix = section.id == 'made_for_you' ||
        tracks.any((t) =>
            (t.extras?['dailyMixId'] ?? '').toString().trim().isNotEmpty);
    final cardSize = isDailyMix ? HomeLayout.mixCard : HomeLayout.shelfCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          section.title,
          badge: badge,
          trailing:
              !isDailyMix && shouldPlayDiscoveryShelfAsQueue(tracks.length)
                  ? HomeSectionPlayButton(
                      onPressed: () async {
                        if (!Get.isRegistered<PlayerController>()) return;
                        final tagged = Get.isRegistered<DiscoveryService>()
                            ? DiscoveryService.tagAll(
                                tracks, sourceForSurface(section.surface))
                            : tracks;
                        final ok = await Get.find<PlayerController>()
                            .playPlayListSong(tagged, 0);
                        if (!ok) _snackDiscoveryPlayFailed();
                      },
                    )
                  : null,
        ),
        HomeShelf(
          cardSize: cardSize,
          itemCount: tracks.length,
          itemBuilder: (context, i) => _DiscoveryCard(
            song: tracks[i],
            shelfTracks: tracks,
            shelfIndex: i,
            surface: section.surface,
            cardSize: cardSize,
            onDismiss: () {
              if (Get.isRegistered<DiscoveryService>()) {
                Get.find<DiscoveryService>()
                    .onDismiss(tracks[i], surface: section.surface);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.song,
    required this.shelfTracks,
    required this.shelfIndex,
    required this.surface,
    required this.onDismiss,
    required this.cardSize,
  });
  final MediaItem song;
  final List<MediaItem> shelfTracks;
  final int shelfIndex;
  final String surface;
  final VoidCallback onDismiss;
  final double cardSize;

  String get _mixId => (song.extras?['dailyMixId'] ?? '').toString().trim();

  String get _mixTitle =>
      (song.extras?['dailyMixTitle'] ?? '').toString().trim();

  Future<void> _playMix(PlayerController player) async {
    final id = _mixId;
    if (id.isEmpty || !Get.isRegistered<DiscoveryService>()) {
      await _openMix();
      return;
    }
    final disc = Get.find<DiscoveryService>();
    GeneratedMix? mix;
    for (final m in disc.dailyMixes) {
      if (m.id == id) {
        mix = m;
        break;
      }
    }
    if (mix == null || mix.tracks.isEmpty) {
      await _openMix();
      return;
    }
    final tracks = <MediaItem>[];
    for (final raw in mix.tracks) {
      try {
        final item = MediaItemBuilder.fromJson(raw);
        if (item.id.isNotEmpty) tracks.add(item);
      } catch (_) {}
    }
    if (tracks.isEmpty) {
      await _openMix();
      return;
    }
    tracks.shuffle();
    final tagged = DiscoveryService.tagAll(tracks, DiscoverySource.dailyMix);
    final ok = await player.playPlayListSong(tagged, 0);
    if (!ok) _snackDiscoveryPlayFailed();
  }

  Future<void> _openMix() async {
    final id = _mixId;
    if (id.isEmpty || !Get.isRegistered<DiscoveryService>()) return;
    final disc = Get.find<DiscoveryService>();
    await disc.materializeMixPlaylists();
    final playlistId = 'RIFF_$id';
    final title = _mixTitle;
    final pl = Playlist(
      title: title.isNotEmpty ? title : 'dailyMix'.tr,
      playlistId: playlistId,
      thumbnailUrl: song.artUri?.toString() ?? Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );
    Get.toNamed(
      ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id,
      arguments: [pl, playlistId],
    );
  }

  List<MediaItem> _collageTracks(String mixId) {
    if (mixId.isEmpty || !Get.isRegistered<DiscoveryService>()) return const [];
    final mixes = Get.find<DiscoveryService>().dailyMixes;
    for (final mix in mixes) {
      if (mix.id != mixId) continue;
      final out = <MediaItem>[];
      for (final raw in mix.tracks) {
        if (out.length >= 4) break;
        try {
          out.add(MediaItemBuilder.fromJson(raw));
        } catch (_) {}
      }
      return out;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final mixTitle = (song.extras?['dailyMixTitle'] ?? '').toString().trim();
    final mixId = (song.extras?['dailyMixId'] ?? '').toString().trim();
    final isMix = mixId.isNotEmpty;
    final reason = mixTitle.isNotEmpty
        ? mixTitle
        : (song.extras?['discoveryReason'] as String? ?? '');
    final collage = isMix ? _collageTracks(mixId) : const <MediaItem>[];
    final primaryTitle = isMix && mixTitle.isNotEmpty ? mixTitle : song.title;
    final secondaryTitle = isMix
        ? (song.artist?.isNotEmpty == true ? song.artist! : song.title)
        : (reason.isNotEmpty ? reason : (song.artist ?? ''));

    return HomeShelfCard(
      size: cardSize,
      title: primaryTitle,
      subtitle: secondaryTitle,
      onTap: () async {
        // Daily Mix cards play the shuffled mix immediately.
        if (mixId.isNotEmpty) {
          await _playMix(player);
          return;
        }
        final tagged = Get.isRegistered<DiscoveryService>()
            ? DiscoveryService.tagAll(shelfTracks, sourceForSurface(surface))
            : shelfTracks;
        final index = shelfIndex.clamp(0, tagged.length - 1);
        final ok = await player.playPlayListSong(tagged, index);
        if (!ok) _snackDiscoveryPlayFailed();
      },
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          constraints: const BoxConstraints(maxWidth: 500),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: sheetBottomInset(ctx, liftAboveMiniPlayer: false),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: ImageWidget(song: song, size: 48),
                    title: Text(song.title, maxLines: 1),
                    subtitle: Text(song.artist ?? '', maxLines: 1),
                  ),
                  if (isMix)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title:
                          Text(mixTitle.isNotEmpty ? mixTitle : 'dailyMix'.tr),
                      onTap: () {
                        Navigator.pop(ctx);
                        _openMix();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: Text('playNext'.tr),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await player.playNext(song);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                        context,
                        ok
                            ? "${"playnextMsg".tr} ${song.title}"
                            : "operationFailed".tr,
                        size: SanckBarSize.MEDIUM,
                      ));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.sensors),
                    title: Text('startRadio'.tr),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await player.startRadio(song);
                      if (!context.mounted || ok) return;
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                        context,
                        "radioNotAvailable".tr,
                        size: SanckBarSize.MEDIUM,
                      ));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.thumb_up_outlined),
                    title: Text("thumbsUp".tr),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (Get.isRegistered<DiscoveryService>()) {
                        Get.find<DiscoveryService>()
                            .onThumbs(song, up: true, surface: surface);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.thumb_down_outlined),
                    title: Text("thumbsDown".tr),
                    onTap: () {
                      Navigator.pop(ctx);
                      onDismiss();
                      if (Get.isRegistered<DiscoveryService>()) {
                        Get.find<DiscoveryService>()
                            .onThumbs(song, up: false, surface: surface);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(snackbar(
                          context, "recommendationRemoved".tr,
                          size: SanckBarSize.MEDIUM));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.graphic_eq),
                    title: Text("similarSongs".tr),
                    onTap: () {
                      Navigator.pop(ctx);
                      showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        constraints: const BoxConstraints(maxWidth: 500),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(10.0)),
                        ),
                        builder: (_) => SimilarSongsSheet(seed: song),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
      art: Stack(
        fit: StackFit.expand,
        children: [
          collage.length >= 4
              ? _MixCollage(tracks: collage, size: cardSize)
              : ImageWidget(song: song, size: cardSize, borderRadius: 0),
          if (isMix)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 8),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MixCollage extends StatelessWidget {
  const _MixCollage({required this.tracks, required this.size});
  final List<MediaItem> tracks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cell = size / 2;
    Widget tile(MediaItem song) => ImageWidget(
          song: song,
          size: cell,
          borderRadius: 0,
        );
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(tracks[0])),
                Expanded(child: tile(tracks[1])),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(tracks[2])),
                Expanded(child: tile(tracks[3])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _snackDiscoveryPlayFailed() => snackOperationFailed();
