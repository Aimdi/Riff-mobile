import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Podcasts/podcast_playback_controls.dart';

import '/models/media_item_extras.dart';
import '/models/thumbnail.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/media_item_video.dart';
import '../../screens/Home/home_layout.dart';
import '../../utils/theme_controller.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'animated_play_button.dart';
import 'backgroud_image.dart';
import 'player_control.dart';
import 'podcast_transcript_sheet.dart';
import 'standard_player.dart';

/// Now-playing screen for podcasts and audiobooks: the episode or chapter
/// is what matters, so the layout is built around position and pacing
/// rather than the song (no lyrics, shuffle, repeat or heart):
///
/// * cover (or the episode's video, when switched on) with a kind label,
/// * the episode / chapter title and the show / book under it,
/// * the current chapter, tappable for the chapter list,
/// * a seek bar with chapter sections,
/// * −10 s · play · +30 s, with previous / next at the edges,
/// * one row of tools: speed, sleep timer, notes or chapters, transcript,
///   video and autoplay.
class LongFormPlayer extends StatelessWidget {
  const LongFormPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final landscape = context.isLandscape;
    return Obx(() {
      final song = pc.currentSong.value;
      final showVideo = song != null &&
          song.canShowPlayerVideo &&
          AlbumArtNLyrics.videoPlaybackEnabledFor(song);
      return Stack(
        children: [
          if (showVideo)
            Positioned.fill(child: ColoredBox(color: theme.primaryColor))
          else ...[
            const BackgroudImage(),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.primaryColor.withOpacity(0.72),
                      theme.primaryColor.withOpacity(0.9),
                      theme.primaryColor,
                    ],
                    stops: const [0, 0.55, 0.85],
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: landscape
                ? Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40, bottom: 90),
                          child: _Art(song: song, showVideo: showVideo),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              bottom: 80 + Get.mediaQuery.padding.bottom),
                          child: const _Controls(),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                          height:
                              Get.mediaQuery.padding.top + PlayerTopBar.height),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _Art(song: song, showVideo: showVideo),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: 80 + Get.mediaQuery.padding.bottom),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: const _Controls(),
                        ),
                      ),
                    ],
                  ),
          ),
          if (!(landscape && GetPlatform.isMobile)) const PlayerTopBar(),
        ],
      );
    });
  }
}

/// Square cover with a soft shadow, or the episode video when enabled.
class _Art extends StatelessWidget {
  const _Art({required this.song, required this.showVideo});
  final MediaItem? song;
  final bool showVideo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final maxW = box.maxWidth.clamp(0.0, 420.0);
      if (showVideo) {
        final w =
            maxW * 9 / 16 <= box.maxHeight ? maxW : box.maxHeight * 16 / 9;
        return Center(child: AlbumArtNLyrics(playerArtImageSize: w));
      }
      final side = maxW < box.maxHeight ? maxW : box.maxHeight;
      final url = Thumbnail(song?.artUri?.toString() ?? '').extraHigh;
      return Center(
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 32,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: url.isEmpty
                ? _fallback(context)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        (side * MediaQuery.devicePixelRatioOf(context)).round(),
                    placeholder: (_, __) =>
                        ColoredBox(color: homeTileColor(context)),
                    errorWidget: (_, __, ___) => CachedNetworkImage(
                      imageUrl: song?.artUri?.toString() ?? '',
                      placeholder: (_, __) =>
                          ColoredBox(color: homeTileColor(context)),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallback(context),
                    ),
                  ),
          ),
        ),
      );
    });
  }

  Widget _fallback(BuildContext context) => ColoredBox(
        color: homeTileColor(context),
        child: Icon(
          song?.isAudiobook == true
              ? Icons.auto_stories_rounded
              : Icons.podcasts_rounded,
          size: 72,
          color: homeMutedColor(context),
        ),
      );
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color ?? RiffSurfaces.textPrimary;
    final accent = theme.colorScheme.secondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final song = pc.currentSong.value;
          final isBook = song?.isAudiobook == true;
          final show = isBook
              ? (song?.album ?? song?.artist ?? '')
              : (song?.artist ?? song?.album ?? '');
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  (isBook ? 'audiobookLabel' : 'podcastLabel').tr.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                song?.title ?? '',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              if (show.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  show,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: fg.withOpacity(0.7),
                  ),
                ),
              ],
            ],
          );
        }),
        const SizedBox(height: 10),
        const _ChapterLine(),
        const SizedBox(height: 10),
        const PlaybackErrorBanner(),
        // Skip-ad pill while inside a detected ad chapter.
        Obx(() => pc.inAdChapter.isFalse
            ? const SizedBox.shrink()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.fast_forward_rounded,
                        size: 18, color: RiffSurfaces.voidBlack),
                    label: Text('skipAd'.tr,
                        style: const TextStyle(
                            color: RiffSurfaces.voidBlack,
                            fontWeight: FontWeight.w700)),
                    backgroundColor: accent,
                    onPressed: pc.skipAd,
                  ),
                ),
              )),
        const RepaintBoundary(child: PlayerSeekScrubber()),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'previous'.tr,
              iconSize: 30,
              onPressed: pc.prev,
              icon: Icon(Icons.skip_previous_rounded, color: fg),
            ),
            LongFormSkipButton(forward: false, color: fg, size: 38),
            const AnimatedPlayButton(key: Key('longFormPlayButton'), size: 76),
            LongFormSkipButton(forward: true, color: fg, size: 38),
            IconButton(
              tooltip: 'next'.tr,
              iconSize: 30,
              onPressed: pc.next,
              icon: Icon(Icons.skip_next_rounded, color: fg),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _ToolRow(),
      ],
    );
  }
}

/// "Chapter 3 · Title" (podcast chapters) or "Chapter 4 of 12" (audiobook
/// tracks), tappable for the full list. Hidden when there is neither.
class _ChapterLine extends StatelessWidget {
  const _ChapterLine();

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    return Obx(() {
      final song = pc.currentSong.value;
      String label = '';
      VoidCallback? onTap;
      if (pc.chapters.isNotEmpty) {
        final pos = pc.progressBarStatus.value.current.inMilliseconds / 1000;
        var idx = 0;
        for (var i = 0; i < pc.chapters.length; i++) {
          if (pc.chapters[i].startSec <= pos) idx = i;
        }
        label = '${idx + 1}/${pc.chapters.length} · ${pc.chapters[idx].title}';
        onTap = () => openChaptersSheet(pc, context);
      } else if (song != null && song.isAudiobook) {
        final queue = pc.currentQueue;
        final i = queue.indexWhere((m) => m.id == song.id);
        if (queue.length > 1 && i >= 0) {
          label = 'chapterOf'
              .trParams({'n': '${i + 1}', 'total': '${queue.length}'});
          onTap = () => openQueueChaptersSheet(context);
        }
      }
      if (label.isEmpty) return const SizedBox(height: 0);
      return Center(
        child: Material(
          color: Colors.white.withOpacity(0.08),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_list_bulleted_rounded,
                      size: 16, color: fg.withOpacity(0.8)),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg.withOpacity(0.9),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: fg.withOpacity(0.6)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Speed · sleep · notes / chapters · transcript · video · autoplay.
class _ToolRow extends StatelessWidget {
  const _ToolRow();

  @override
  Widget build(BuildContext context) {
    final pc = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color ?? RiffSurfaces.textPrimary;
    final accent = theme.colorScheme.secondary;
    return Obx(() {
      final song = pc.currentSong.value;
      final isBook = song?.isAudiobook == true;
      final transcriptUrl = (song?.extras?['transcriptUrl'] ?? '').toString();
      final canVideo = song?.canShowPlayerVideo == true;
      final videoOn = canVideo && AlbumArtNLyrics.videoPlaybackEnabledFor(song);
      final settings = Get.find<SettingsScreenController>();
      final autoOn = settings.podcastContinuousPlaybackEnabled.value;
      final sleepOn = pc.isSleepTimerActive.isTrue;

      Widget tool(IconData icon, String label, VoidCallback? onTap,
          {bool active = false, String? badge}) {
        final c = active ? accent : fg.withOpacity(0.85);
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: c),
                  const SizedBox(height: 4),
                  Text(
                    badge ?? label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Center(
                  child: pc.isCurrentSongPodcast
                      ? PodcastSpeedButton(color: fg)
                      : PlayerSpeedButton(color: fg)),
            ),
            tool(
              sleepOn ? Icons.bedtime : Icons.bedtime_outlined,
              'sleepTimer'.tr,
              () => showSleepTimerSheet(
                  pc.homeScaffoldkey.currentContext ?? context),
              active: sleepOn,
              badge:
                  sleepOn ? sleepTimerBadge(pc.timerDurationLeft.value) : null,
            ),
            if (isBook)
              tool(Icons.format_list_bulleted_rounded, 'chapters'.tr,
                  () => openQueueChaptersSheet(context))
            else
              tool(Icons.notes_rounded, 'shownotes'.tr,
                  () => openShownotesSheet(pc, context)),
            if (transcriptUrl.isNotEmpty)
              tool(
                Icons.subtitles_outlined,
                'transcript'.tr,
                () => PodcastTranscriptSheet.open(
                  context,
                  url: transcriptUrl,
                  type: '${song?.extras?['transcriptType'] ?? ''}',
                ),
              ),
            if (canVideo)
              tool(
                videoOn ? Icons.videocam_rounded : Icons.videocam_outlined,
                'video'.tr,
                () async {
                  await AlbumArtNLyrics.setVideoPlaybackEnabled(song, !videoOn);
                  pc.currentSong.refresh();
                },
                active: videoOn,
              ),
            if (!isBook)
              tool(
                Icons.playlist_play_rounded,
                'autoplayShort'.tr,
                () => settings.togglePodcastContinuousPlayback(!autoOn),
                active: autoOn,
              ),
          ],
        ),
      );
    });
  }
}

/// Audiobook chapters are the tracks in the queue: list them, mark the
/// current one, tap to jump.
void openQueueChaptersSheet(BuildContext context) {
  final pc = Get.find<PlayerController>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => Obx(() {
        final queue = pc.currentQueue.toList();
        final currentId = pc.currentSong.value?.id;
        final accent = Theme.of(ctx).colorScheme.secondary;
        return ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
          itemCount: queue.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text('chapters'.tr,
                    style: Theme.of(ctx).textTheme.titleLarge),
              );
            }
            final m = queue[i - 1];
            final playing = m.id == currentId;
            final d = m.duration;
            return ListTile(
              leading: SizedBox(
                width: 28,
                child: playing
                    ? Icon(Icons.graphic_eq_rounded, color: accent)
                    : Text('$i',
                        textAlign: TextAlign.center,
                        style: homeCardSubtitleStyle(ctx)),
              ),
              title: Text(
                m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: playing ? accent : null,
                  fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: d == null
                  ? null
                  : Text(
                      d.inHours > 0
                          ? '${d.inHours}h ${d.inMinutes.remainder(60)}m'
                          : '${d.inMinutes}m',
                      style: homeCardSubtitleStyle(ctx)),
              onTap: () {
                Navigator.pop(ctx);
                pc.seekByIndex(i - 1);
              },
            );
          },
        );
      }),
    ),
  );
}
