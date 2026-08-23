import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/ui/navigator.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/widgets/collection_play.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import 'podcasts_screen.dart';

/// Phone: always 2 columns so covers stay large. Wider screens get 3–4.
int podcastSubsColumnCount(double width) {
  if (width >= 1100) return 4;
  if (width >= 720) return 3;
  return 2;
}

const double kPodcastSubsHPad = 16;
const double kPodcastSubsGap = 14;
const double kPodcastSubsTextBlock = 58;

double podcastSubsCoverSize(double maxWidth, int columns) {
  return (maxWidth - kPodcastSubsHPad * 2 - kPodcastSubsGap * (columns - 1)) /
      columns;
}

double podcastSubsMainAxisExtent(double coverSize) =>
    coverSize + 8 + kPodcastSubsTextBlock;

SliverGridDelegate podcastSubsGridDelegate(double width) {
  final columns = podcastSubsColumnCount(width);
  final cover = podcastSubsCoverSize(width, columns);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: kPodcastSubsGap,
    mainAxisSpacing: kPodcastSubsGap,
    mainAxisExtent: podcastSubsMainAxisExtent(cover),
  );
}

const EdgeInsets kPodcastSubsGridPadding =
    EdgeInsets.fromLTRB(16, 8, 16, 200);

/// Large cover-filling tile for the Subs grid (and folder contents).
class PodcastCoverTile extends StatelessWidget {
  const PodcastCoverTile({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.cover,
    this.onTap,
    this.onLongPress,
    this.onPlay,
    this.badge,
    this.showPlay = true,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final Widget? cover;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlay;
  final Widget? badge;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: cover ?? _art(context),
                  ),
                  if (badge != null)
                    Positioned(left: 8, top: 8, child: badge!),
                  if (showPlay)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _PlayFab(onPressed: onPlay ?? onTap),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.2,
                letterSpacing: -0.15,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: muted,
                    height: 1.25,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _art(BuildContext context) {
    final theme = Theme.of(context);
    final url = imageUrl ?? '';
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      child: Center(
        child: Image.asset(
          'assets/icons/album.png',
          width: 72,
          height: 72,
          color: theme.iconTheme.color?.withOpacity(0.45),
          colorBlendMode: BlendMode.srcATop,
          errorBuilder: (_, __, ___) => Icon(
            Icons.album_outlined,
            size: 56,
            color: theme.iconTheme.color?.withOpacity(0.4),
          ),
        ),
      ),
    );
    if (url.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: (420 * MediaQuery.devicePixelRatioOf(context)).round(),
      errorWidget: (_, __, ___) => fallback,
      placeholder: (_, __) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
      ),
    );
  }
}

class _PlayFab extends StatelessWidget {
  const _PlayFab({this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black54,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
        ),
      ),
    );
  }
}

bool isYoutubeChannelPodcast(Playlist podcast) {
  if (podcast.kind == 'yt_channel') return true;
  return RegExp(r'^UC[\w-]{20,}$').hasMatch(podcast.playlistId);
}

String libraryPodcastSubtitle(Playlist podcast) {
  final count = podcast.songCount?.toString();
  if (count != null && count.isNotEmpty && count != 'null') {
    return '$count ${"songs".tr}';
  }
  final desc = podcast.description?.toString() ?? '';
  if (desc.isNotEmpty && desc != 'Playlist') return desc;
  return '';
}

Widget youtubeChannelBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.65),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(Icons.ondemand_video, size: 14, color: Colors.white),
  );
}

Future<void> playLibraryPodcast(Playlist podcast) async {
  try {
    if (isPodcastCollection(kind: podcast.kind, id: podcast.playlistId)) {
      final tracks = await loadCollectionPlayTracks(
        isAlbum: false,
        id: podcast.playlistId,
        isLibraryItem: true,
        isPipedPlaylist: podcast.isPipedPlaylist,
        isCloudPlaylist: podcast.isCloudPlaylist,
      );
      if (tracks.isNotEmpty) {
        final ok = await playCollectionTracksAsPodcast(
          tracks: tracks,
          title: podcast.title,
        );
        if (ok) return;
      }
    }
    final ok = await playCollection(
      isAlbum: false,
      id: podcast.playlistId,
      title: podcast.title,
      isLibraryItem: true,
      isPipedPlaylist: podcast.isPipedPlaylist,
      isCloudPlaylist: podcast.isCloudPlaylist,
    );
    if (!ok) {
      snackOperationFailed();
      openLibraryPodcast(podcast);
    }
  } catch (_) {
    snackOperationFailed();
    openLibraryPodcast(podcast);
  }
}

void openLibraryPodcast(Playlist podcast) {
  Get.toNamed(
    ScreenNavigationSetup.playlistScreen,
    id: ScreenNavigationSetup.id,
    arguments: [podcast, podcast.playlistId, false],
  );
}

Future<void> playOrOpenRssPodcast(Map<String, dynamic> podcast) async {
  final ok = await playPodcastShow(podcast);
  if (ok) return;
  Get.to(() => PodcastEpisodesScreen(podcast: podcast));
}

String rssArtworkUrl(Map<String, dynamic> podcast) {
  return Thumbnail((podcast['artwork'] ?? '').toString()).high;
}
