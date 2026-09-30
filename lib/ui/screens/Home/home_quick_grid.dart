import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/services/discovery/discovery_service.dart';
import '/services/discovery/discovery_tag.dart';
import '/services/discovery/discovery_types.dart';
import '/services/podcast_progress_service.dart';
import '/ui/navigator.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/snackbar.dart';
import 'home_layout.dart';
import 'podcast_continue.dart';

/// Top of Home: resume tiles, then library and discovery shortcuts as one
/// grid of art + title tiles. Phones: library on the left, discovery on the
/// right. Wide screens: one row each.
class HomeQuickGrid extends StatelessWidget {
  const HomeQuickGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final disc = Get.isRegistered<DiscoveryService>()
        ? Get.find<DiscoveryService>()
        : null;
    final library = <Widget>[
      _ShortcutTile(
        title: 'favorites'.tr,
        icon: Icons.favorite_rounded,
        colors: const [Color(0xFF4B22D6), Color(0xFF9D85FF)],
        onTap: () => _playLibraryBox(context,
            id: 'LIBFAV', title: 'favorites'.tr, shuffle: true),
        onLongPress: () => _openLibraryPlaylist('LIBFAV', 'favorites'.tr),
      ),
      _ShortcutTile(
        title: 'recentlyPlayed'.tr,
        icon: Icons.history_rounded,
        colors: const [Color(0xFF0D4F9E), Color(0xFF45B4F5)],
        onTap: () => _playLibraryBox(context,
            id: 'LIBRP', title: 'recentlyPlayed'.tr, mostRecentFirst: true),
        onLongPress: () => _openLibraryPlaylist('LIBRP', 'recentlyPlayed'.tr),
      ),
      _ShortcutTile(
        title: 'downloads'.tr,
        icon: Icons.download_done_rounded,
        colors: const [Color(0xFF0A5E5A), Color(0xFF27C2B4)],
        onTap: () => _playLibraryBox(context,
            id: 'SongDownloads', title: 'downloads'.tr),
        onLongPress: () =>
            _openLibraryPlaylist('SongDownloads', 'downloads'.tr),
      ),
    ];
    final discovery = <Widget>[
      _ShortcutTile(
        title: 'freshFinds'.tr,
        icon: Icons.auto_awesome_rounded,
        colors: const [Color(0xFF0B6B31), Color(0xFF2BD66B)],
        onTap: () {
          if (disc == null) return;
          _playTracks(context, () => disc.engine.freshFinds(),
              DiscoverySource.freshFinds);
        },
      ),
      _ShortcutTile(
        title: 'rediscover'.tr,
        icon: Icons.replay_rounded,
        colors: const [Color(0xFFA2400F), Color(0xFFFF9A45)],
        onTap: () {
          if (disc == null) return;
          _playTracks(context, () => disc.engine.rediscover(),
              DiscoverySource.discover);
        },
      ),
      _ShortcutTile(
        title: 'releaseRadar'.tr,
        icon: Icons.new_releases_rounded,
        colors: const [Color(0xFF8E1540), Color(0xFFFF5A8A)],
        onTap: () {
          if (disc == null) return;
          _playTracks(context, () => disc.engine.releaseRadar(),
              DiscoverySource.discover);
        },
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
      child: LayoutBuilder(builder: (context, constraints) {
        final rows = constraints.maxWidth >= 560
            ? [library, discovery]
            : [
                for (var i = 0; i < library.length; i++)
                  [library[i], discovery[i]],
              ];
        return Column(
          children: [
            const _ResumeRow(),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: HomeLayout.tileGap),
              _TileRow(tiles: rows[i]),
            ],
          ],
        );
      }),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tiles});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: HomeLayout.tileGap),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// Continue listening (saved queue) and the newest in-progress podcast
/// episode. One item fills the row; two share it.
class _ResumeRow extends StatelessWidget {
  const _ResumeRow();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<PlayerController>()) {
      return const SizedBox.shrink();
    }
    final player = Get.find<PlayerController>();
    return Obx(() {
      // Read every observable before any early return: an Obx that builds
      // without touching one throws in GetX, and release builds paint that
      // as a full-height grey box over the rest of Home.
      final current = player.currentSong.value;
      final showSession = player.showContinueListening.value;
      final sessionItem = player.continueListeningItem.value;
      final sessionTitle = player.continueListeningTitle.value;

      final idle = current == null || player.initFlagForPlayer;
      final rows = PodcastProgressService.inProgress();
      final latest = latestPodcastContinue(rows);
      final episode =
          latest == null ? null : PodcastProgressService.toMediaItem(latest);
      final showEpisode = episode != null &&
          shouldShowPodcastContinueChip(
            hasEpisode: true,
            currentSongId: current?.id,
            continueEpisodeId: episode.id,
          );
      final showResume = showSession && idle;
      if (!showResume && !showEpisode) return const SizedBox.shrink();
      final both = showResume && showEpisode;

      return Padding(
        padding: const EdgeInsets.only(bottom: HomeLayout.tileGap),
        child: _TileRow(tiles: [
          if (showResume)
            _SessionTile(
              player: player,
              item: sessionItem,
              title: sessionTitle,
              compact: both,
            ),
          if (showEpisode)
            _EpisodeTile(
              player: player,
              episode: episode,
              rows: rows,
              compact: both,
            ),
        ]),
      );
    });
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.player,
    required this.item,
    required this.title,
    required this.compact,
  });

  final PlayerController player;
  final MediaItem? item;
  final String title;

  /// Sharing the row with the podcast tile: no room for the close button,
  /// so dismiss moves to long-press.
  final bool compact;

  /// The tile hides as soon as resume starts, so a failure is reported
  /// through the app-level snackbar instead of this (gone) context.
  Future<void> _resume() async {
    if (!await player.resumeSavedSession()) snackOperationFailed();
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text('continueListening'.tr),
              onTap: () {
                Navigator.pop(ctx);
                _resume();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text('dismiss'.tr),
              onTap: () {
                Navigator.pop(ctx);
                player.dismissContinueListening();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = [
      item?.title ?? title,
      if ((item?.artist ?? '').isNotEmpty) item!.artist!,
    ].join(' · ');
    return _QuickTile(
      art: item != null
          ? ImageWidget(
              song: item, size: HomeLayout.tileHeight, borderRadius: 0)
          : const _GradientArt(
              colors: [Color(0xFF0B6B31), Color(0xFF2BD66B)],
              icon: Icons.play_arrow_rounded,
            ),
      // Half-width: the play badge says "resume"; the title gets both lines.
      kicker: compact ? null : 'continueListening'.tr,
      playBadge: compact,
      title: label,
      onTap: _resume,
      onLongPress: () => _showSheet(context),
      trailing: compact
          ? null
          : IconButton(
              tooltip: 'dismiss'.tr,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: homeMutedColor(context)),
              onPressed: player.dismissContinueListening,
            ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.player,
    required this.episode,
    required this.rows,
    required this.compact,
  });

  final PlayerController player;
  final MediaItem episode;
  final List<Map<String, dynamic>> rows;
  final bool compact;

  Future<void> _resume() async {
    final queue = podcastContinueQueue(rows);
    if (queue.isEmpty) return;
    final pos = PodcastProgressService.positionMs(queue.first.id) ?? 0;
    if (pos > 0) player.armResume(queue.first.id, pos);
    final ok = await player.playPlayListSong(queue, 0,
        source: DiscoverySource.podcast);
    if (!ok) snackOperationFailed();
  }

  @override
  Widget build(BuildContext context) {
    return _QuickTile(
      art: episode.artUri != null
          ? ImageWidget(
              song: episode, size: HomeLayout.tileHeight, borderRadius: 0)
          : const _GradientArt(
              colors: [Color(0xFF4B22D6), Color(0xFF9D85FF)],
              icon: Icons.podcasts_rounded,
            ),
      kicker: compact ? null : 'continuePodcast'.tr,
      playBadge: compact,
      title: episode.title,
      progress: PodcastProgressService.progress(episode.id),
      onTap: _resume,
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.title,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return _QuickTile(
      art: _GradientArt(colors: colors, icon: icon),
      title: title,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Spotify-style compact tile: square art flush left, bold title.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.art,
    required this.title,
    this.kicker,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.playBadge = false,
    this.progress,
  });

  final Widget art;
  final String title;

  /// Small accent label above the title (resume tiles).
  final String? kicker;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Accent play badge over the art (resume tiles without a kicker).
  final bool playBadge;

  /// 0..1 listened fraction drawn along the bottom edge (podcasts).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final radius = BorderRadius.circular(RiffTokens.radiusSm);
    return LayoutBuilder(builder: (context, constraints) {
      // Half-width tiles on small phones: smaller art so "Rediscover" or
      // "Downloads" still fits on one line instead of splitting mid-word.
      final narrow = constraints.maxWidth < 160;
      final artSize = narrow ? 48.0 : HomeLayout.tileHeight;
      return Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              ConstrainedBox(
                // Grows instead of overflowing at large system font sizes.
                constraints: BoxConstraints(minHeight: artSize),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: artSize,
                      child: playBadge
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                art,
                                Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black38,
                                            blurRadius: 6),
                                      ],
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded,
                                        size: 18, color: Colors.black),
                                  ),
                                ),
                              ],
                            )
                          : art,
                    ),
                    SizedBox(width: narrow ? 8 : 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (kicker != null)
                              Text(
                                kicker!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                  height: 1.3,
                                ),
                              ),
                            Text(
                              title,
                              maxLines: kicker == null ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: homeCardTitleStyle(context).copyWith(
                                fontSize: narrow ? 12.5 : 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    trailing ?? SizedBox(width: narrow ? 6 : 8),
                  ],
                ),
              ),
              if (progress != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2.5,
                    color: accent,
                    backgroundColor: homeMutedColor(context)?.withOpacity(0.25),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _GradientArt extends StatelessWidget {
  const _GradientArt({required this.colors, required this.icon});

  final List<Color> colors;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 24)),
    );
  }
}

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

/// Play a library Hive box as a queue; an empty box opens the list instead.
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
    final ok = await Get.find<PlayerController>()
        .playPlayListSong(tracks, 0, source: sourceFromPlaylistId(id));
    if (!ok) snackOperationFailed();
  } catch (_) {
    if (!context.mounted) return;
    _openLibraryPlaylist(id, title);
  }
}

/// Fetch a generated list (Fresh finds, Rediscover, New releases) and play it.
Future<void> _playTracks(
  BuildContext context,
  Future<List<MediaItem>> Function() load,
  DiscoverySource source,
) async {
  ScaffoldMessenger.of(context)
      .showSnackBar(snackbar(context, 'loading'.tr, size: SanckBarSize.SMALL));
  try {
    final tracks = await load();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          snackbar(context, 'mixEmpty'.tr, size: SanckBarSize.MEDIUM));
      return;
    }
    final tagged = Get.isRegistered<DiscoveryService>()
        ? DiscoveryService.tagAll(tracks, source)
        : tracks;
    final ok = await Get.find<PlayerController>().playPlayListSong(tagged, 0);
    if (!ok) snackOperationFailed();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
        snackbar(context, 'networkError'.tr, size: SanckBarSize.MEDIUM));
  }
}
