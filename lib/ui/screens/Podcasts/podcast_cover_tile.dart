import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/ui/navigator.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/collection_play.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import 'podcasts_screen.dart';

/// 3 columns on regular phones (2 on narrow ones), more on tablets.
int podcastSubsColumnCount(double width) {
  if (width >= 1100) return 6;
  if (width >= 720) return 4;
  if (width >= 380) return 3;
  return 2;
}

const double kPodcastSubsHPad = RiffSpacing.md;
const double kPodcastSubsGap = RiffSpacing.md;
const double kPodcastSubsTextBlock = 40;

double podcastSubsCoverSize(double maxWidth, int columns) {
  return (maxWidth - kPodcastSubsHPad * 2 - kPodcastSubsGap * (columns - 1)) /
      columns;
}

double podcastSubsMainAxisExtent(double coverSize) =>
    coverSize + RiffSpacing.sm + kPodcastSubsTextBlock;

SliverGridDelegate podcastSubsGridDelegate(double width,
    {TextScaler textScaler = TextScaler.noScaling}) {
  final columns = podcastSubsColumnCount(width);
  final cover = podcastSubsCoverSize(width, columns);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: kPodcastSubsGap,
    mainAxisSpacing: kPodcastSubsGap + RiffSpacing.xs,
    mainAxisExtent:
        cover + RiffSpacing.sm + textScaler.scale(kPodcastSubsTextBlock),
  );
}

const EdgeInsets kPodcastSubsGridPadding = EdgeInsets.only(
    left: RiffSpacing.md,
    top: RiffSpacing.xs,
    right: RiffSpacing.md,
    bottom: RiffSpacing.listEnd);

/// Large cover-filling tile for the Subs grid (and folder contents): a §5.3
/// card — no background, art radius 8, titleMedium / bodyMedium, gap 8.
class PodcastCoverTile extends StatelessWidget {
  const PodcastCoverTile({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.playlist,
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

  /// Library / YouTube shows — uses [ImageWidget] so art matches the old grid.
  final Playlist? playlist;
  final Widget? cover;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlay;
  final Widget? badge;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffRadii.sm),
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
                    borderRadius: BorderRadius.circular(RiffRadii.sm),
                    child: cover ?? _art(context),
                  ),
                  if (badge != null)
                    Positioned(
                        left: RiffSpacing.sm,
                        top: RiffSpacing.sm,
                        child: badge!),
                  if (showPlay)
                    Positioned(
                      right: RiffSpacing.sm,
                      bottom: RiffSpacing.sm,
                      child: _PlayFab(onPressed: onPlay ?? onTap),
                    ),
                ],
              ),
            ),
            const SizedBox(height: RiffSpacing.sm),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: RiffSpacing.xxs),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _art(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Image.asset(
          'assets/icons/album.png',
          width: RiffComponentSizes.showRowArt,
          height: RiffComponentSizes.showRowArt,
          color: muted,
          colorBlendMode: BlendMode.srcATop,
          errorBuilder: (_, __, ___) => Icon(
            Icons.album_outlined,
            size: RiffComponentSizes.emptyStateIcon,
            color: muted,
          ),
        ),
      ),
    );
    final urls = Thumbnail.coverUrls(imageUrl ?? '');
    if (playlist != null) {
      return LayoutBuilder(builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final size = (side.isFinite && side > 0) ? side : 180.0;
        return ImageWidget(
          playlist: playlist,
          size: size,
          borderRadius: 0,
        );
      });
    }
    if (urls.isEmpty) return fallback;
    final waiting = ColoredBox(color: theme.colorScheme.surfaceContainerLow);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.biggest.shortestSide;
      final decodeSide = ((side.isFinite && side > 0 ? side : 220) * dpr)
          .round()
          .clamp(64, 1600);

      Widget layer(int i) {
        return CachedNetworkImage(
          imageUrl: urls[i],
          httpHeaders: kCoverImageHeaders,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: decodeSide,
          filterQuality: FilterQuality.medium,
          alignment: Alignment.center,
          placeholder: (_, __) => waiting,
          errorWidget: (_, __, ___) =>
              i + 1 < urls.length ? layer(i + 1) : fallback,
        );
      }

      return layer(0);
    });
  }
}

/// Accent play circle on a cover (a play button, §2.5); flat, no shadow.
class _PlayFab extends StatelessWidget {
  const _PlayFab({this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: RiffComponentSizes.coverPlay,
          height: RiffComponentSizes.coverPlay,
          child: Icon(Icons.play_arrow_rounded,
              color: scheme.onPrimary, size: RiffComponentSizes.trailingIcon),
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

Widget youtubeChannelBadge(BuildContext context) {
  final riff = RiffColors.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(
        horizontal: RiffSpacing.xs, vertical: RiffSpacing.xxs),
    decoration: BoxDecoration(
      color: riff.scrim.withOpacity(0.65),
      borderRadius: BorderRadius.circular(RiffRadii.xs),
    ),
    child: Icon(Icons.ondemand_video,
        size: RiffSizes.chipGlyph, color: riff.onImage),
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
  // Stored artwork; [PodcastCoverTile] upgrades and falls back itself.
  return (podcast['artwork'] ?? '').toString();
}
