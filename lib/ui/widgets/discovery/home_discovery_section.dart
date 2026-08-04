import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../navigator.dart';
import '../../player/player_controller.dart';
import '../../utils/sheet_insets.dart';
import '../image_widget.dart';
import '../snackbar.dart';
import 'similar_songs_sheet.dart';

/// Horizontal carousel for a personal discovery section on Home.
class HomeDiscoverySection extends StatelessWidget {
  const HomeDiscoverySection({super.key, required this.section});
  final DiscoverySection section;

  @override
  Widget build(BuildContext context) {
    final tracks =
        section.tracks.map((m) => MediaItemBuilder.fromJson(m)).toList();
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 24, bottom: 10, right: 12),
          child: Text(
            section.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  letterSpacing: -0.35,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 12, right: 12),
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final song = tracks[i];
              return Padding(
                padding: EdgeInsets.only(right: i == tracks.length - 1 ? 0 : 12),
                child: _DiscoveryCard(
                  song: song,
                  surface: section.surface,
                  onDismiss: () {
                    if (Get.isRegistered<DiscoveryService>()) {
                      Get.find<DiscoveryService>()
                          .onDismiss(song, surface: section.surface);
                    }
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.song,
    required this.surface,
    required this.onDismiss,
  });
  final MediaItem song;
  final String surface;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final mixTitle = (song.extras?['dailyMixTitle'] ?? '').toString().trim();
    final mixId = (song.extras?['dailyMixId'] ?? '').toString().trim();
    final reason = mixTitle.isNotEmpty
        ? mixTitle
        : (song.extras?['discoveryReason'] as String? ?? '');
    return SizedBox(
      width: 112,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Daily Mix cards open the full mix playlist, not one lead track.
          if (mixId.isNotEmpty && Get.isRegistered<DiscoveryService>()) {
            final disc = Get.find<DiscoveryService>();
            await disc.materializeMixPlaylists();
            final playlistId = 'RIFF_$mixId';
            final pl = Playlist(
              title: mixTitle.isNotEmpty ? mixTitle : 'dailyMix'.tr,
              playlistId: playlistId,
              thumbnailUrl: song.artUri?.toString() ??
                  Playlist.thumbPlaceholderUrl,
              isCloudPlaylist: false,
            );
            Get.toNamed(
              ScreenNavigationSetup.playlistScreen,
              id: ScreenNavigationSetup.id,
              arguments: [pl, playlistId],
            );
            return;
          }
          final tagged = Get.isRegistered<DiscoveryService>()
              ? DiscoveryService.withSource(song, DiscoverySource.discover)
              : song;
          player.pushSongToQueue(tagged);
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
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(10.0)),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ImageWidget(song: song, size: 112),
            ),
            const SizedBox(height: 8),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).textTheme.titleMedium?.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.15,
                    )),
            const SizedBox(height: 2),
            Text(
              reason.isNotEmpty ? reason : (song.artist ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact Home shortcuts: 3×2 destination tiles (Zone A).
/// Soft surface tiles with icon over label — not content carousels.
class HomeShortcutGrid extends StatelessWidget {
  const HomeShortcutGrid({super.key});

  void _openLibraryPlaylist(String id, String title) {
    final pl = Playlist(
      title: title,
      playlistId: id,
      thumbnailUrl: Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
    );
    Get.toNamed(
      ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id,
      arguments: [pl, id],
    );
  }

  Future<void> _playTracks(
    BuildContext context,
    Future<List<MediaItem>> Function() load,
    DiscoverySource source,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
      context,
      'loading'.tr,
      size: SanckBarSize.SMALL,
    ));
    try {
      final tracks = await load();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (tracks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'mixEmpty'.tr,
          size: SanckBarSize.MEDIUM,
        ));
        return;
      }
      final tagged = Get.isRegistered<DiscoveryService>()
          ? DiscoveryService.tagAll(tracks, source)
          : tracks;
      await Get.find<PlayerController>().playPlayListSong(tagged, 0);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        'networkError'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final disc = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>()
        : null;
    final theme = Theme.of(context);

    final items = <_ShortcutItem>[
      _ShortcutItem(
        title: 'favorites'.tr,
        icon: Icons.favorite_outline,
        onTap: () => _openLibraryPlaylist('LIBFAV', 'favorites'.tr),
      ),
      _ShortcutItem(
        title: 'recentlyPlayed'.tr,
        icon: Icons.history,
        onTap: () => _openLibraryPlaylist('LIBRP', 'recentlyPlayed'.tr),
      ),
      _ShortcutItem(
        title: 'freshFinds'.tr,
        icon: Icons.auto_awesome_outlined,
        onTap: () {
          if (disc == null) return;
          _playTracks(
            context,
            () => disc.engine.freshFinds(),
            DiscoverySource.discover,
          );
        },
      ),
      _ShortcutItem(
        title: 'rediscover'.tr,
        icon: Icons.history_toggle_off,
        onTap: () {
          if (disc == null) return;
          _playTracks(
            context,
            () => disc.engine.rediscover(),
            DiscoverySource.discover,
          );
        },
      ),
      _ShortcutItem(
        title: 'releaseRadar'.tr,
        icon: Icons.new_releases_outlined,
        onTap: () {
          if (disc == null) return;
          _playTracks(
            context,
            () => disc.engine.releaseRadar(),
            DiscoverySource.discover,
          );
        },
      ),
      _ShortcutItem(
        title: 'downloads'.tr,
        icon: Icons.download_outlined,
        onTap: () => _openLibraryPlaylist('SongDownloads', 'downloads'.tr),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final tileW = (constraints.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items.map((e) {
              return SizedBox(
                width: tileW,
                height: 80,
                child: Material(
                  color: theme.cardColor.withOpacity(
                    theme.brightness == Brightness.dark ? 0.92 : 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.dividerColor.withOpacity(0.7),
                      width: 0.5,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: e.onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(e.icon,
                              size: 22,
                              color: theme.textTheme.titleMedium?.color),
                          const SizedBox(height: 6),
                          Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _ShortcutItem {
  _ShortcutItem({
    required this.title,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}
