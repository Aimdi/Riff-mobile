import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/media_Item_builder.dart';
import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../player/player_controller.dart';
import '../image_widget.dart';
import '../snackbar.dart';
import 'similar_songs_sheet.dart';

/// Horizontal carousel for a personal discovery section on Home.
class HomeDiscoverySection extends StatelessWidget {
  const HomeDiscoverySection({super.key, required this.section});
  final DiscoverySection section;

  @override
  Widget build(BuildContext context) {
    final tracks = section.tracks
        .map((m) => MediaItemBuilder.fromJson(m))
        .toList();
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, top: 15, bottom: 5, right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (section.reason.isNotEmpty)
                Text(
                  section.reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
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
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final tagged = Get.isRegistered<DiscoveryService>()
              ? DiscoveryService.withSource(song, DiscoverySource.discover)
              : song;
          player.pushSongToQueue(tagged);
        },
        onLongPress: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            constraints: const BoxConstraints(maxWidth: 500),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
            ),
            builder: (ctx) => SafeArea(
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
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ImageWidget(song: song, size: 120),
              ),
              const SizedBox(height: 6),
              Text(song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                reason.isNotEmpty ? reason : (song.artist ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shortcut grid (2×3) for Home top: Liked, Daily Mix 1, Fresh Finds, etc.
class HomeShortcutGrid extends StatelessWidget {
  const HomeShortcutGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final disc = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>()
        : null;
    final mixes = disc?.dailyMixes ?? <GeneratedMix>[].obs;

    return Obx(() {
      final daily = mixes.isNotEmpty ? mixes.first : null;
      final items = <_ShortcutItem>[
        _ShortcutItem(
          title: "favorites".tr,
          icon: Icons.favorite,
          onTap: () {
            Get.find<PlayerController>().homeScaffoldkey.currentState;
            // Navigate via library favorites playlist
            // Users already know Favorites in Library; play recent favs if any.
          },
        ),
        _ShortcutItem(
          title: daily?.title ?? "dailyMix".tr,
          icon: Icons.album,
          onTap: () {
            if (daily == null || daily.tracks.isEmpty) return;
            final tracks =
                daily.tracks.map((m) => MediaItemBuilder.fromJson(m)).toList();
            final tagged = DiscoveryService.tagAll(
                tracks, DiscoverySource.dailyMix);
            Get.find<PlayerController>().playPlayListSong(tagged, 0);
          },
        ),
        _ShortcutItem(
          title: "freshFinds".tr,
          icon: Icons.explore,
          onTap: () async {
            if (disc == null) return;
            final tracks = await disc.engine.freshFinds();
            if (tracks.isEmpty) return;
            Get.find<PlayerController>().playPlayListSong(tracks, 0);
          },
        ),
        _ShortcutItem(
          title: "rediscover".tr,
          icon: Icons.history_toggle_off,
          onTap: () async {
            if (disc == null) return;
            final tracks = await disc.engine.rediscover();
            if (tracks.isEmpty) return;
            Get.find<PlayerController>().playPlayListSong(tracks, 0);
          },
        ),
        _ShortcutItem(
          title: "recentlyPlayed".tr,
          icon: Icons.history,
          onTap: () {},
        ),
        _ShortcutItem(
          title: "releaseRadar".tr,
          icon: Icons.new_releases_outlined,
          onTap: () async {
            if (disc == null) return;
            final tracks = await disc.engine.releaseRadar();
            if (tracks.isEmpty) return;
            Get.find<PlayerController>().playPlayListSong(tracks, 0);
          },
        ),
      ];

      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: items
              .map((e) => Material(
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: e.onTap,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(e.icon, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        ),
      );
    });
  }
}

class _ShortcutItem {
  _ShortcutItem({required this.title, required this.icon, required this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}
