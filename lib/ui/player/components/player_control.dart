import '/ui/player/long_form_queue.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '/ui/player/components/podcast_transcript_sheet.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '/utils/content_filters.dart';
import '/services/podcast_service.dart' show PodcastChapter;
import '../../screens/Settings/settings_screen_controller.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/discovery/player_similar_row.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../../widgets/snackbar.dart';
import '../chapter_marks.dart';
import '../player_controller.dart';
import '../radio_continuation.dart';
import '../player_media_nav.dart';
import 'playback_error_actions.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _TitleBlock(playerController: playerController)),
              const SizedBox(width: 8),
              FavoriteHeartButton(
                isFav: playerController.isCurrentSongFav,
                onToggleFav: playerController.toggleFavourite,
                song: () => playerController.currentSong.value,
                iconSize: 26,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Visible reason when a song won't start — snackbar alone is easy to miss.
          const PlaybackErrorBanner(),
          // Spotify-style straight seek bar. Podcasts with chapters split
          // into sections; music is one line. Phone volume stays on hardware.
          // Own layer: the 10 Hz progress tick must not repaint the whole
          // player (album art, controls) up to the root.
          const RepaintBoundary(child: PlayerSeekScrubber()),
          const SizedBox(height: 6),
          Obx(() => playerController.usesLongFormTransport
              ? _podcastControls(playerController, context)
              : _musicControls(playerController, context)),
          const SizedBox(height: 10),
          Obx(() => playerController.usesLongFormTransport
              ? _podcastActions(playerController, context)
              : _musicActions(playerController, context)),
          // Similar songs are music-only, and only where the cover keeps
          // most of the screen.
          Obx(() => playerController.usesLongFormTransport ||
                  MediaQuery.sizeOf(context).height < 820
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: PlayerSimilarRow(),
                )),
        ]);
  }

  /// Lyrics · sleep timer · radio · add to playlist · share. Everything
  /// else for the song is in the ⋮ sheet.
  Widget _musicActions(
      PlayerController playerController, BuildContext context) {
    final song = playerController.currentSong.value;
    return PlayerActionBar(actions: [
      PlayerAction(
        icon: Icons.lyrics_outlined,
        activeIcon: Icons.lyrics,
        tooltip: 'lyrics'.tr,
        active: playerController.showLyricsflag.isTrue,
        onTap: playerController.showLyrics,
      ),
      _sleepAction(playerController, context),
      PlayerAction(
        icon: Icons.sensors_rounded,
        tooltip: 'startRadio'.tr,
        onTap: song == null
            ? null
            : () async {
                final ok = await playerController.startRadio(song);
                if (!context.mounted || ok) return;
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                  context,
                  "radioNotAvailable".tr,
                  size: SanckBarSize.MEDIUM,
                ));
              },
      ),
      PlayerAction(
        icon: Icons.playlist_add_rounded,
        tooltip: 'addToPlaylist'.tr,
        onTap:
            song == null ? null : () => showAddToPlaylistSheet(context, [song]),
      ),
      PlayerAction(
        icon: Icons.share_outlined,
        tooltip: 'shareSong'.tr,
        onTap: song == null
            ? null
            : () => Share.share(SongLinkShare.shareText(song)),
      ),
    ]);
  }

  /// Autoplay · shownotes · chapters · transcript · sleep timer.
  Widget _podcastActions(
      PlayerController playerController, BuildContext context) {
    final song = playerController.currentSong.value;
    final transcriptUrl = (song?.extras?['transcriptUrl'] ?? '').toString();
    final settings = Get.find<SettingsScreenController>();
    final autoOn = settings.podcastContinuousPlaybackEnabled.value;
    final isPodcast = playerController.isCurrentSongPodcast;
    return PlayerActionBar(actions: [
      if (isPodcast)
        PlayerAction(
          icon: Icons.playlist_play_rounded,
          tooltip: 'autoplayEpisodes'.tr,
          active: autoOn,
          onTap: () => settings.togglePodcastContinuousPlayback(!autoOn),
        ),
      if (isPodcast)
        PlayerAction(
          icon: Icons.info_outline_rounded,
          tooltip: 'shownotes'.tr,
          onTap: () => openShownotesSheet(playerController, context),
        ),
      if (playerController.chapters.isNotEmpty)
        PlayerAction(
          icon: Icons.format_list_bulleted_rounded,
          tooltip: 'chapters'.tr,
          onTap: () => _openChapters(playerController, context),
        ),
      if (transcriptUrl.isNotEmpty)
        PlayerAction(
          icon: Icons.subtitles_outlined,
          tooltip: 'transcript'.tr,
          onTap: () => PodcastTranscriptSheet.open(
            context,
            url: transcriptUrl,
            type: '${song?.extras?['transcriptType'] ?? ''}',
          ),
        ),
      _sleepAction(playerController, context),
    ]);
  }

  PlayerAction _sleepAction(
      PlayerController playerController, BuildContext context) {
    final on = playerController.isSleepTimerActive.isTrue;
    return PlayerAction(
      icon: Icons.bedtime_outlined,
      activeIcon: Icons.bedtime,
      tooltip: 'sleepTimer'.tr,
      active: on,
      badge:
          on ? sleepTimerBadge(playerController.timerDurationLeft.value) : null,
      onTap: () => showSleepTimerSheet(
          playerController.homeScaffoldkey.currentContext ?? context),
    );
  }

  Widget _musicControls(
      PlayerController playerController, BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium!.color!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
            tooltip: 'shuffle'.tr,
            iconSize: 22,
            onPressed: playerController.toggleShuffleMode,
            icon: Obx(() => _ToggleIcon(
                  icon: Ionicons.shuffle,
                  on: playerController.isShuffleModeEnabled.value,
                  color: fg,
                ))),
        _previousButton(playerController, context),
        const AnimatedPlayButton(key: Key("playButton"), size: 68),
        _nextButton(playerController, context),
        Obx(() {
          final state = playerController.repeatState;
          return IconButton(
              tooltip: state == 2
                  ? "repeatOne".tr
                  : state == 1
                      ? "repeatAll".tr
                      : "repeat".tr,
              iconSize: 22,
              onPressed: playerController.cycleRepeatMode,
              icon: _ToggleIcon(
                // repeat_one shows the "1" badge (Spotify-style).
                icon: state == 2
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                on: state != 0,
                color: fg,
              ));
        }),
      ],
    );
  }

  /// AntennaPod-style transport: speed · −10s · play/pause · +30s · next.
  Widget _podcastControls(
      PlayerController playerController, BuildContext context) {
    final color = Theme.of(context).textTheme.titleMedium!.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Skip ad" pill — shown while playback is inside a detected ad chapter.
        Obx(() => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: playerController.inAdChapter.isFalse
                  ? const SizedBox(height: 0, width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ActionChip(
                        avatar: Icon(Icons.fast_forward,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSecondary),
                        label: Text('skipAd'.tr,
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                                fontWeight: FontWeight.w600)),
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary,
                        onPressed: playerController.skipAd,
                      ),
                    ),
            )),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            PlayerSpeedButton(color: color),
            IconButton(
              tooltip: '−10s',
              iconSize: 34,
              onPressed: () =>
                  playerController.seekBy(const Duration(seconds: -10)),
              icon: Icon(Icons.replay_10_rounded, color: color),
            ),
            const AnimatedPlayButton(key: Key('podcastPlayButton'), size: 68),
            IconButton(
              tooltip: '+30s',
              iconSize: 34,
              onPressed: () =>
                  playerController.seekBy(const Duration(seconds: 30)),
              icon: Icon(Icons.forward_30_rounded, color: color),
            ),
            _nextButton(playerController, context),
          ],
        ),
      ],
    );
  }

  void _openChapters(PlayerController playerController, BuildContext context) =>
      openChaptersSheet(playerController, context);
}

void openChaptersSheet(
    PlayerController playerController, BuildContext context) {
  final chapters = playerController.chapters;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) {
        String fmt(double sec) {
          final d = Duration(milliseconds: (sec * 1000).round());
          final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
          final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
          final h = d.inHours;
          return h > 0 ? '$h:$m:$s' : '$m:$s';
        }

        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          itemCount: chapters.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Text('chapters'.tr,
                    style: Theme.of(ctx).textTheme.titleLarge),
              );
            }
            final c = chapters[i - 1];
            return ListTile(
              leading: Icon(
                c.isAd ? Icons.campaign_outlined : Icons.play_arrow_rounded,
                color: c.isAd
                    ? Theme.of(ctx).colorScheme.error
                    : Theme.of(ctx).colorScheme.secondary,
              ),
              title:
                  Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(fmt(c.startSec)),
              onTap: () {
                Navigator.pop(ctx);
                playerController.seek(
                  Duration(milliseconds: (c.startSec * 1000).round()),
                );
              },
            );
          },
        );
      },
    ),
  );
}

void openShownotesSheet(
    PlayerController playerController, BuildContext context) {
  final song = playerController.currentSong.value;
  final notes = episodeNotes(song).trim();
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
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song?.title ?? '', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(song?.artist ?? '', style: Theme.of(ctx).textTheme.titleSmall),
            const Divider(height: 24),
            Text(
              notes.isEmpty ? "noShownotes".tr : notes,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _previousButton(
    PlayerController playerController, BuildContext context) {
  return IconButton(
    tooltip: 'previous'.tr,
    icon: Icon(
      Icons.skip_previous_rounded,
      color: Theme.of(context).textTheme.titleMedium!.color,
    ),
    iconSize: 38,
    onPressed: playerController.prev,
  );
}

/// Why the current item won't play, with retry / skip actions. Shown above
/// the seek bar in both the music and the long-form player.
class PlaybackErrorBanner extends StatelessWidget {
  const PlaybackErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      final err = playerController.playbackError.value;
      if (err == null || err.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.error.withOpacity(0.12),
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            border: Border.all(
                color: theme.colorScheme.error.withOpacity(0.35), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    err,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: theme.textTheme.titleMedium?.color,
                    ),
                  ),
                ),
                PlaybackErrorActions(
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Podcast playback-speed control: shows the current speed, tap cycles through
/// common podcast speeds. Persists via SettingsScreenController like the
/// speed/pitch dialog.
class PlayerSpeedButton extends StatelessWidget {
  const PlayerSpeedButton({super.key, required this.color});
  final Color? color;

  static const _speeds = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

  void _cycle() {
    final settings = Get.find<SettingsScreenController>();
    final cur = settings.playbackSpeed.value;
    final idx = _speeds.indexWhere((s) => (s - cur).abs() < 0.01);
    final next = _speeds[(idx + 1) % _speeds.length];
    settings.setBox.put("playbackSpeed", next);
    settings.playbackSpeed.value = next;
    Get.find<PlayerController>()
        .setSpeedAndPitch(speed: next, pitch: settings.playbackPitch.value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsScreenController>();
    return Tooltip(
      message: 'speed'.tr,
      child: InkWell(
        onTap: _cycle,
        customBorder: const StadiumBorder(),
        child: Container(
          width: 52,
          height: 32,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                  color: (color ?? RiffSurfaces.textPrimary).withOpacity(0.35)),
            ),
          ),
          child: Obx(() => Text(
                speedLabel(settings.playbackSpeed.value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              )),
        ),
      ),
    );
  }
}

/// 1.0 → "1×", 1.25 → "1.25×", 1.5 → "1.5×".
String speedLabel(double speed) {
  var s = speed.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$s×';
}

/// Remaining sleep time for the action-bar badge: "1h", "12m", "45s".
/// End-of-song timers count down the song's remaining time.
String sleepTimerBadge(int secondsLeft) {
  if (secondsLeft <= 0) return '';
  if (secondsLeft >= 3600) return '${(secondsLeft / 3600).ceil()}h';
  if (secondsLeft >= 60) return '${(secondsLeft / 60).ceil()}m';
  return '${secondsLeft}s';
}

/// One entry in [PlayerActionBar].
class PlayerAction {
  const PlayerAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.activeIcon,
    this.active = false,
    this.badge,
  });
  final IconData icon;
  final IconData? activeIcon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  /// Short text under the icon while [active] (e.g. sleep time left).
  final String? badge;
}

/// Row of equal-width icon actions under the transport. Active actions use
/// the accent colour, so state is visible without labels.
class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({super.key, required this.actions});
  final List<PlayerAction> actions;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      children: [
        for (final a in actions)
          Expanded(
            child: Tooltip(
              message: a.tooltip,
              child: InkResponse(
                onTap: a.onTap,
                radius: 26,
                child: SizedBox(
                  height: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        a.active ? (a.activeIcon ?? a.icon) : a.icon,
                        size: 22,
                        semanticLabel: a.tooltip,
                        color: a.active ? accent : fg.withOpacity(0.72),
                      ),
                      if (a.active && (a.badge ?? '').isNotEmpty)
                        Text(
                          a.badge!,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shuffle / repeat: full colour with an accent dot when on, dimmed when off.
class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon(
      {required this.icon, required this.on, required this.color});
  final IconData icon;
  final bool on;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return SizedBox.square(
      dimension: 22,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 22, color: on ? accent : color.withOpacity(0.5)),
          if (on)
            Positioned(
              bottom: -8,
              child: Container(
                width: 4,
                height: 4,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Title + artist, left aligned; long names scroll. Tapping opens the
/// album / artist.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.playerController});
  final PlayerController playerController;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        RiffSurfaces.textPrimary;
    return ShaderMask(
      // Fade the right edge so a scrolling title doesn't hard-clip.
      shaderCallback: (rect) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.9, 1],
      ).createShader(Rect.fromLTWH(0, 0, rect.width, rect.height)),
      blendMode: BlendMode.dstIn,
      child: Obx(() {
        final song = playerController.currentSong.value;
        final title =
            (song != null && song.title.isNotEmpty) ? song.title : '—';
        final artist = (song?.artist ?? '').isNotEmpty ? song!.artist! : '—';
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: SizedBox(
            key: ValueKey<String>(song?.id ?? 'none'),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openCurrentAlbum(playerController),
                  child: Marquee(
                    delay: const Duration(milliseconds: 1500),
                    duration: const Duration(seconds: 10),
                    id: '${song?.id}_title',
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: fg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => openCurrentArtist(playerController),
                  child: Marquee(
                    delay: const Duration(milliseconds: 1500),
                    duration: const Duration(seconds: 10),
                    id: '${song?.id}_subtitle',
                    child: Text(
                      artist,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: fg.withOpacity(0.66),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final canNext = canSkipNext(
      queueEmpty: playerController.currentQueue.isEmpty,
      isLast: playerController.currentQueue.isNotEmpty &&
          playerController.currentQueue.last.id ==
              playerController.currentSong.value?.id,
      shuffleOn: playerController.isShuffleModeEnabled.isTrue,
      queueLoopOn: playerController.isQueueLoopModeEnabled.isTrue,
      radioOn: playerController.isRadioModeOn,
    );
    return IconButton(
        tooltip: 'next'.tr,
        icon: Icon(
          Icons.skip_next_rounded,
          color: !canNext
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 38,
        onPressed: canNext ? playerController.next : null);
  });
}

/// Format a playback position as m:ss (or h:mm:ss for long tracks).
/// Unknown / unset totals render as an em dash instead of NA or 0:00.
String _fmtDuration(Duration d, {bool allowZero = true}) {
  if (!allowZero && d <= Duration.zero) return '—';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Straight seek bar (Spotify). Podcast chapters split the line into
/// sections; music / chapter-less episodes stay one rounded track.
class PlayerSeekScrubber extends StatefulWidget {
  const PlayerSeekScrubber({super.key});

  @override
  State<PlayerSeekScrubber> createState() => PlayerSeekScrubberState();
}

class PlayerSeekScrubberState extends State<PlayerSeekScrubber> {
  double? _dragFrac;
  Duration? _dragPosition;
  Duration? _seekTarget;
  Timer? _seekHold;

  // Chapter marks only change with the episode's chapters / duration, not
  // with every 10 Hz progress tick — memoize them.
  List<double> _marks = const [];
  List<PodcastChapter> _marksChapters = const [];
  int _marksTotalMs = -1;

  List<double> _chapterMarks(List<PodcastChapter> chapters, int totalMs) {
    var same =
        totalMs == _marksTotalMs && chapters.length == _marksChapters.length;
    for (var i = 0; same && i < chapters.length; i++) {
      same = identical(chapters[i], _marksChapters[i]);
    }
    if (!same) {
      _marksTotalMs = totalMs;
      _marksChapters = List.of(chapters);
      _marks = podcastChapterMarks(chapters, totalMs / 1000.0);
    }
    return _marks;
  }

  /// Moves the thumb only — the actual seek happens once, on release
  /// ([_commitScrub]); seeking on every drag update floods the player.
  void _scrubTo(double dx, double width, Duration total) {
    if (total.inMilliseconds <= 0 || width <= 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    final pos = total * f;
    _seekHold?.cancel();
    _seekTarget = null;
    setState(() {
      _dragFrac = f;
      _dragPosition = pos;
    });
  }

  /// Seeks once and keeps the thumb at the target until the player reports
  /// a position near it (or a short timeout), so it doesn't snap back to the
  /// pre-seek position for a few ticks.
  void _commitScrub(PlayerController c) {
    final pos = _dragPosition;
    if (pos == null) return _endScrub();
    c.seek(pos);
    _seekTarget = pos;
    _seekHold?.cancel();
    _seekHold = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _endScrub();
    });
  }

  void _endScrub() {
    _seekHold?.cancel();
    _seekTarget = null;
    if (_dragFrac == null && _dragPosition == null) return;
    setState(() {
      _dragFrac = null;
      _dragPosition = null;
    });
  }

  @override
  void dispose() {
    _seekHold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(builder: (controller) {
      final status = controller.progressBarStatus.value;
      final target = _seekTarget;
      if (target != null &&
          (status.current - target).abs() < const Duration(seconds: 1)) {
        // Player caught up with the committed seek — follow live progress.
        _seekHold?.cancel();
        _seekTarget = null;
        _dragFrac = null;
        _dragPosition = null;
      }
      final totalMs = status.total.inMilliseconds;
      final liveFrac = totalMs > 0
          ? (status.current.inMilliseconds / totalMs).clamp(0.0, 1.0)
          : 0.0;
      final frac = _dragFrac ?? liveFrac;
      final marks = _chapterMarks(controller.chapters, totalMs);
      final timeStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: 12,
            color: RiffSurfaces.textMuted,
            fontWeight: FontWeight.w500,
          );
      final currentLabel = _fmtDuration(_dragPosition ?? status.current);
      final totalLabel = _fmtDuration(status.total, allowZero: false);
      final played = Theme.of(context).sliderTheme.activeTrackColor ??
          Theme.of(context).colorScheme.secondary;
      final rest = (Theme.of(context).sliderTheme.inactiveTrackColor ??
              RiffSurfaces.hairline)
          .withOpacity(0.55);

      return Padding(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total),
                onTapUp: (_) => _commitScrub(controller),
                onTapCancel: _endScrub,
                onHorizontalDragStart: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total),
                onHorizontalDragUpdate: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total),
                onHorizontalDragEnd: (_) => _commitScrub(controller),
                onHorizontalDragCancel: _endScrub,
                child: SizedBox(
                  height: 36,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SectionTrackPainter(
                      progress: frac,
                      marks: marks,
                      playedColor: played,
                      restColor: rest,
                      thumbColor: RiffSurfaces.textPrimary,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(currentLabel, style: timeStyle),
                Text(totalLabel, style: timeStyle),
              ],
            ),
          ],
        ),
      );
    });
  }
}

/// Spotify-style rounded track. [marks] are 0–1 chapter boundaries that
/// punch a gap so each section reads as its own pill.
class _SectionTrackPainter extends CustomPainter {
  _SectionTrackPainter({
    required this.progress,
    required this.marks,
    required this.playedColor,
    required this.restColor,
    required this.thumbColor,
  });

  final double progress;
  final List<double> marks;
  final Color playedColor;
  final Color restColor;
  final Color thumbColor;

  static const _gap = 3.0;
  static const _trackH = 4.0;
  static const _thumb = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final top = cy - _trackH / 2;
    final bounds = <double>[0, ...marks.where((m) => m > 0 && m < 1), 1];
    for (var i = 0; i < bounds.length - 1; i++) {
      final left = bounds[i] * size.width + (i == 0 ? 0 : _gap / 2);
      final right =
          bounds[i + 1] * size.width - (i == bounds.length - 2 ? 0 : _gap / 2);
      if (right - left < 1) continue;
      final rect = RRect.fromLTRBR(
          left, top, right, top + _trackH, const Radius.circular(99));
      canvas.drawRRect(rect, Paint()..color = restColor);
      final playedRight = (size.width * progress).clamp(left, right);
      if (playedRight > left + 0.5) {
        canvas.drawRRect(
          RRect.fromLTRBR(
              left, top, playedRight, top + _trackH, const Radius.circular(99)),
          Paint()..color = playedColor,
        );
      }
    }
    final tx =
        (size.width * progress).clamp(_thumb / 2, size.width - _thumb / 2);
    canvas.drawCircle(
      Offset(tx, cy),
      _thumb / 2,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SectionTrackPainter old) =>
      old.progress != progress ||
      old.playedColor != playedColor ||
      old.restColor != restColor ||
      old.thumbColor != thumbColor ||
      !_listEq(old.marks, marks);

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
