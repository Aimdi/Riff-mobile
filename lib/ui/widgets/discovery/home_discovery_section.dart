import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../models/media_Item_builder.dart';
import '../../../models/playlist.dart';
import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../navigator.dart';
import '../../player/play_queue_order.dart';
import '../../player/player_controller.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/sheet_insets.dart';
import '../../utils/theme_controller.dart';
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

    final isDailyMix = section.id == 'made_for_you' ||
        tracks.any((t) =>
            (t.extras?['dailyMixId'] ?? '').toString().trim().isNotEmpty);
    final cardSize = isDailyMix ? 124.0 : 112.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 24, bottom: 10, right: 12),
          child: Row(
            children: [
              Expanded(
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
              if (!isDailyMix && shouldPlayDiscoveryShelfAsQueue(tracks.length))
                IconButton(
                  tooltip: 'playAll'.tr,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  onPressed: () {
                    if (!Get.isRegistered<PlayerController>()) return;
                    final tagged = Get.isRegistered<DiscoveryService>()
                        ? DiscoveryService.tagAll(
                            tracks, DiscoverySource.discover)
                        : tracks;
                    Get.find<PlayerController>().playPlayListSong(tagged, 0);
                  },
                ),
            ],
          ),
        ),
        SizedBox(
          height: isDailyMix ? 178 : 156,
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
                  shelfTracks: tracks,
                  shelfIndex: i,
                  surface: section.surface,
                  cardSize: cardSize,
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

  String get _mixId =>
      (song.extras?['dailyMixId'] ?? '').toString().trim();

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
    await player.playPlayListSong(tagged, 0);
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

    return SizedBox(
      width: cardSize,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
        onTap: () async {
          // Daily Mix cards play the shuffled mix immediately.
          if (mixId.isNotEmpty) {
            await _playMix(player);
            return;
          }
          final tagged = Get.isRegistered<DiscoveryService>()
              ? DiscoveryService.tagAll(
                  shelfTracks, DiscoverySource.discover)
              : shelfTracks;
          final index = shelfIndex.clamp(0, tagged.length - 1);
          await player.playPlayListSong(tagged, index);
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
                        title: Text(mixTitle.isNotEmpty
                            ? mixTitle
                            : 'dailyMix'.tr),
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
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
                  child: collage.length >= 4
                      ? _MixCollage(tracks: collage, size: cardSize)
                      : ImageWidget(song: song, size: cardSize),
                ),
                if (isMix)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.62),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(primaryTitle,
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
              secondaryTitle,
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

  Future<void> _playLibraryBox(
    BuildContext context, {
    required String id,
    required String title,
    bool shuffle = false,
    bool mostRecentFirst = false,
  }) async {
    try {
      final box = Hive.isBoxOpen(id) ? Hive.box(id) : await Hive.openBox(id);
      var tracks = <MediaItem>[];
      for (final raw in box.values) {
        try {
          final item = MediaItemBuilder.fromJson(raw);
          if (item.id.isNotEmpty) tracks.add(item);
        } catch (_) {}
      }
      if (mostRecentFirst) {
        tracks = tracks.reversed.toList();
      }
      if (tracks.isEmpty) {
        _openLibraryPlaylist(id, title);
        return;
      }
      if (shuffle) {
        tracks.shuffle();
      }
      await Get.find<PlayerController>().playPlayListSong(tracks, 0);
    } catch (_) {
      if (!context.mounted) return;
      _openLibraryPlaylist(id, title);
    }
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
        onTap: () => _playLibraryBox(
          context,
          id: 'LIBFAV',
          title: 'favorites'.tr,
          shuffle: true,
        ),
        onLongPress: () => _openLibraryPlaylist('LIBFAV', 'favorites'.tr),
      ),
      _ShortcutItem(
        title: 'recentlyPlayed'.tr,
        icon: Icons.history,
        onTap: () => _playLibraryBox(
          context,
          id: 'LIBRP',
          title: 'recentlyPlayed'.tr,
          mostRecentFirst: true,
        ),
        onLongPress: () =>
            _openLibraryPlaylist('LIBRP', 'recentlyPlayed'.tr),
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
        onTap: () => _playLibraryBox(
          context,
          id: 'SongDownloads',
          title: 'downloads'.tr,
        ),
        onLongPress: () =>
            _openLibraryPlaylist('SongDownloads', 'downloads'.tr),
      ),
    ];

    return Padding(
      // Tighter bottom so daily mixes rise closer under shortcuts.
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final tileW = (constraints.maxWidth - gap * 2) / 3;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items.map((e) {
              return SizedBox(
                width: tileW,
                height: 68,
                child: Material(
                  color: theme.brightness == Brightness.dark
                      ? RiffSurfaces.elevatedSoft.withOpacity(0.85)
                      : theme.cardColor.withOpacity(0.95),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                    side: BorderSide(
                      color: theme.brightness == Brightness.dark
                          ? RiffSurfaces.hairline.withOpacity(0.35)
                          : theme.dividerColor.withOpacity(0.35),
                      width: RiffTokens.hairline,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                    onTap: e.onTap,
                    onLongPress: e.onLongPress,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(e.icon,
                              size: 20,
                              color: theme.textTheme.titleMedium?.color),
                          const SizedBox(height: 4),
                          Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
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
    this.onLongPress,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}
