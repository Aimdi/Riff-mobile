import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Podcasts/podcast_segment_ui.dart';

import '/ui/screens/Podcasts/podcast_playback_controls.dart';

import '/models/media_item_extras.dart';
import '/models/thumbnail.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/utils/media_item_video.dart';
import '../../screens/Home/home_layout.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../player_controller.dart';
import 'albumart_lyrics.dart';
import 'animated_play_button.dart';
import 'backgroud_image.dart';
import 'player_control.dart';
import '/services/podcast_transcripts.dart';
import 'podcast_player_tint.dart';
import 'podcast_transcript_sheet.dart';
import 'standard_player.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_theme.dart';
import '/ui/theme/riff_tokens.dart';

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
      // Black page (§ Phase 6). Podcasts: the show's artwork colour as a
      // top gradient of at most 20%; otherwise the cover shows through at
      // most 20% at the top, as on the music player.
      final bg = theme.colorScheme.surface;
      final tint = PodcastPlayerTint.of(song);
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: bg)),
          if (!showVideo) ...[
            if (tint == null) const BackgroudImage(),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: tint == null
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            bg.withOpacity(1 - RiffPalette.playerTintOpacity),
                            bg,
                          ],
                          stops: const [0, 0.6],
                        )
                      : PodcastPlayerTint.backdrop(tint, bg),
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.xxl),
            child: landscape
                ? Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                              top: RiffSpacing.unit * 10, bottom: 90),
                          child: _Art(song: song, showVideo: showVideo),
                        ),
                      ),
                      const SizedBox(width: RiffSpacing.xxl),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              bottom: RiffSpacing.unit * 20 +
                                  Get.mediaQuery.padding.bottom),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: RiffSpacing.md),
                          child: _Art(song: song, showVideo: showVideo),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            bottom: RiffSpacing.unit * 20 +
                                Get.mediaQuery.padding.bottom),
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

/// Square cover (radius 8, no shadow), or the episode video when enabled.
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
        child: SizedBox(
          width: side,
          height: side,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RiffRadii.sm),
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
          size: RiffComponentSizes.longFormFallbackIcon,
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
    final scheme = theme.colorScheme;
    // Transport glyphs in the primary text colour (§ Phase 6).
    final fg = scheme.onSurface;
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
              // Kind label: a quiet hairline pill (the accent is for
              // interactive elements only).
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: RiffSpacing.sm, vertical: RiffSpacing.xxs),
                decoration: ShapeDecoration(
                  shape: StadiumBorder(
                    side: BorderSide(color: theme.dividerColor, width: 0),
                  ),
                ),
                child: Text(
                  (isBook ? 'audiobookLabel' : 'podcastLabel').tr.toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                song?.title ?? '',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RiffTextStyles.of(context).playerTitle,
              ),
              if (show.trim().isNotEmpty) ...[
                const SizedBox(height: RiffSpacing.xs),
                Text(
                  show,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
        Obx(() => PodcastSkipPill(
              visible: pc.inAdChapter.isTrue,
              label: podcastSkipPillLabel(pc),
              onPressed: pc.skipAd,
              padding: const EdgeInsets.only(bottom: RiffSpacing.sm),
            )),
        const RepaintBoundary(child: PlayerSeekScrubber()),
        const SizedBox(height: RiffSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'previous'.tr,
              iconSize: RiffComponentSizes.longFormEdge,
              onPressed: pc.prev,
              icon: Icon(Icons.skip_previous_rounded, color: fg),
            ),
            LongFormSkipButton(
                forward: false,
                color: fg,
                size: RiffComponentSizes.longFormSkip),
            // Accent circle with the on-accent glyph (§ Phase 6).
            AnimatedPlayButton(
                key: const Key('longFormPlayButton'),
                size: RiffComponentSizes.longFormPlay,
                iconColor: scheme.onSecondary),
            LongFormSkipButton(
                forward: true,
                color: fg,
                size: RiffComponentSizes.longFormSkip),
            IconButton(
              tooltip: 'next'.tr,
              iconSize: RiffComponentSizes.longFormEdge,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
      // §5.6 unselected chip: transparent, hairline divider border.
      return Center(
        child: Material(
          color: Colors.transparent,
          shape: StadiumBorder(
              side: BorderSide(color: theme.dividerColor, width: 0)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(
                  left: RiffSpacing.md,
                  top: RiffSpacing.sm,
                  right: RiffSpacing.sm,
                  bottom: RiffSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_list_bulleted_rounded,
                      size: RiffComponentSizes.chipLeadingIcon,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(width: RiffSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: RiffComponentSizes.chipChevron,
                      color: scheme.onSurfaceVariant),
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
    // §5 Phase 6 action row: 20 dp glyphs in the secondary text colour,
    // the accent when on.
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.secondary;
    return Obx(() {
      final song = pc.currentSong.value;
      final isBook = song?.isAudiobook == true;
      final hasTranscript =
          PodcastTranscriptService.available(song) && song != null;
      final canVideo = song?.canShowPlayerVideo == true;
      final videoOn = canVideo && AlbumArtNLyrics.videoPlaybackEnabledFor(song);
      final settings = Get.find<SettingsScreenController>();
      final autoOn = settings.podcastContinuousPlaybackEnabled.value;
      final sleepOn = pc.isSleepTimerActive.isTrue;

      Widget tool(IconData icon, String label, VoidCallback? onTap,
          {bool active = false, String? badge}) {
        final c = active ? accent : muted;
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(RiffRadii.sm),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: RiffSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: RiffComponentSizes.trailingIcon, color: c),
                  const SizedBox(height: RiffSpacing.xs),
                  Text(
                    badge ?? label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: c),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Straight on the page: no card behind the row (§2.1).
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Center(
                  child: pc.isCurrentSongPodcast
                      ? PodcastSpeedButton(color: muted)
                      : PlayerSpeedButton(color: muted)),
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
            if (hasTranscript)
              tool(
                Icons.subtitles_outlined,
                'transcript'.tr,
                () => PodcastTranscriptSheet.open(context, song),
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
          padding: const EdgeInsets.only(
              left: RiffSpacing.sm,
              right: RiffSpacing.sm,
              bottom: RiffSpacing.x3l),
          itemCount: queue.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(
                    left: RiffSpacing.md,
                    right: RiffSpacing.md,
                    bottom: RiffSpacing.md),
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
                style: (playing
                        ? Theme.of(ctx).textTheme.titleMedium
                        : Theme.of(ctx).textTheme.bodyLarge)
                    ?.copyWith(color: playing ? accent : null),
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
