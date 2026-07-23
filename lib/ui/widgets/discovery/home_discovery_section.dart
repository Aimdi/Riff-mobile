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
          padding: const EdgeInsets.only(left: 12, top: 18, bottom: 10, right: 12),
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
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 2, right: 8),
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final song = tracks[i];
              return _DiscoveryCard(
                song: song,
                surface: section.surface,
                onDismiss: () {
                  if (Get.isRegistered<DiscoveryService>()) {
                    Get.find<DiscoveryService>()
                        .onDismiss(song, surface: section.surface);
                  }
                },
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
    final reason = song.extras?['discoveryReason'] as String? ?? '';
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ImageWidget(song: song, size: 120),
              ),
              const SizedBox(height: 7),
              Text(song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).textTheme.titleMedium?.color,
                        fontWeight: FontWeight.w600,
                      )),
              Text(
                reason.isNotEmpty ? reason : (song.artist ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Home shortcuts: Favorites, Daily Mix, Fresh Finds, etc.
/// Soft surface tiles (not solid accent blocks) with working navigation.
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
    final mixes = disc?.dailyMixes ?? <GeneratedMix>[].obs;
    final theme = Theme.of(context);
    final onSurface = theme.textTheme.titleMedium?.color ?? Colors.white;

    return Obx(() {
      final daily = mixes.isNotEmpty ? mixes.first : null;
      MediaItem? dailyArt;
      if (daily != null && daily.tracks.isNotEmpty) {
        try {
          dailyArt = MediaItemBuilder.fromJson(daily.tracks.first);
        } catch (_) {}
      }

      final items = <_ShortcutItem>[
        _ShortcutItem(
          title: 'favorites'.tr,
          icon: Icons.favorite_outline,
          onTap: () => _openLibraryPlaylist('LIBFAV', 'favorites'.tr),
        ),
        _ShortcutItem(
          title: daily?.title ?? 'dailyMix'.tr,
          icon: Icons.album_outlined,
          art: dailyArt,
          onTap: () {
            if (daily == null || daily.tracks.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(snackbar(
                context,
                'mixEmpty'.tr,
                size: SanckBarSize.MEDIUM,
              ));
              return;
            }
            final tracks =
                daily.tracks.map((m) => MediaItemBuilder.fromJson(m)).toList();
            final tagged =
                DiscoveryService.tagAll(tracks, DiscoverySource.dailyMix);
            Get.find<PlayerController>().playPlayListSong(tagged, 0);
          },
        ),
        _ShortcutItem(
          title: 'freshFinds'.tr,
          icon: Icons.explore_outlined,
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
          title: 'recentlyPlayed'.tr,
          icon: Icons.history,
          onTap: () => _openLibraryPlaylist('LIBRP', 'recentlyPlayed'.tr),
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
      ];

      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Two columns, quiet tiles — matches Home content density.
            final tileW = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((e) {
                return SizedBox(
                  width: tileW,
                  height: 52,
                  child: Material(
                    color: Theme.of(context).cardColor.withOpacity(
                          Theme.of(context).brightness == Brightness.dark
                              ? 0.92
                              : 1,
                        ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.7),
                        width: 0.5,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: e.onTap,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: e.art != null
                                  ? ImageWidget(song: e.art!, size: 52)
                                  : ColoredBox(
                                      color: onSurface.withOpacity(0.08),
                                      child: Icon(
                                        e.icon,
                                        size: 22,
                                        color: onSurface.withOpacity(0.85),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: -0.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    });
  }
}

class _ShortcutItem {
  _ShortcutItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.art,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final MediaItem? art;
}
