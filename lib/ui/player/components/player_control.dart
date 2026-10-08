import '/ui/player/long_form_queue.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/ui/screens/Podcasts/podcast_segment_ui.dart';

import '/ui/screens/Podcasts/podcast_playback_controls.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '/services/podcast_transcripts.dart';
import '/ui/player/components/podcast_transcript_sheet.dart';
import '/ui/utils/theme_controller.dart';
import '/services/podcast_service.dart' show PodcastChapter;
import '../../screens/Settings/settings_screen_controller.dart';
import '../../widgets/discovery/player_similar_row.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/sleep_timer_bottom_sheet.dart';
import '../chapter_marks.dart';
import '../player_controller.dart';
import '../radio_continuation.dart';
import '../player_media_nav.dart';
import 'playback_error_actions.dart';
import 'standard_player.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_theme.dart';
import '/ui/theme/riff_tokens.dart';

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
              const SizedBox(width: 10),
              _RoundAction(
                child: IconButton(
                  tooltip: 'moreOptions'.tr,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 46, height: 46),
                  icon: const Icon(Icons.more_vert_rounded, size: 24),
                  onPressed: () => openNowPlayingSheet(playerController),
                ),
              ),
              const SizedBox(width: 10),
              _RoundAction(
                child: FavoriteHeartButton(
                  isFav: playerController.isCurrentSongFav,
                  onToggleFav: () {
                    if (playerController.isCurrentSongFav.isFalse) {
                      HapticFeedback.lightImpact();
                    }
                    playerController.toggleFavourite();
                  },
                  song: () => playerController.currentSong.value,
                  iconSize: 24,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 46, height: 46),
                ),
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
          // Music has no button row: lyrics, sleep timer, radio, add to
          // playlist and share are in the ⋮ sheet.
          Obx(() => playerController.usesLongFormTransport
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _podcastActions(playerController, context),
                )
              : const SizedBox.shrink()),
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

  /// Autoplay · shownotes · chapters · transcript · sleep timer.
  Widget _podcastActions(
      PlayerController playerController, BuildContext context) {
    final song = playerController.currentSong.value;
    final hasTranscript =
        PodcastTranscriptService.available(song) && song != null;
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
      if (hasTranscript)
        PlayerAction(
          icon: Icons.subtitles_outlined,
          tooltip: 'transcript'.tr,
          onTap: () => PodcastTranscriptSheet.open(context, song),
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
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;
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
        AnimatedPlayButton(
            key: const Key("playButton"),
            size: 68,
            iconColor: scheme.onSecondary),
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
        Obx(() => PodcastSkipPill(
              visible: playerController.inAdChapter.isTrue,
              label: podcastSkipPillLabel(playerController),
              onPressed: playerController.skipAd,
              padding: const EdgeInsets.only(bottom: RiffSpacing.sm),
            )),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            playerController.isCurrentSongPodcast
                ? PodcastSpeedButton(color: color)
                : PlayerSpeedButton(color: color),
            LongFormSkipButton(forward: false, color: color, size: 34),
            const AnimatedPlayButton(key: Key('podcastPlayButton'), size: 68),
            LongFormSkipButton(forward: true, color: color, size: 34),
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
          padding: const EdgeInsets.only(
              left: RiffSpacing.sm,
              right: RiffSpacing.sm,
              bottom: RiffSpacing.xxl),
          itemCount: chapters.length + 1,
          itemBuilder: (ctx, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(
                    left: RiffSpacing.md,
                    top: RiffSpacing.xs,
                    right: RiffSpacing.md,
                    bottom: RiffSpacing.md),
                child: Text('chapters'.tr,
                    style: Theme.of(ctx).textTheme.titleLarge),
              );
            }
            final c = chapters[i - 1];
            return ListTile(
              leading: Icon(
                c.isAd ? Icons.campaign_outlined : Icons.play_arrow_rounded,
                size: RiffComponentSizes.headerIcon,
                color: c.isAd
                    ? Theme.of(ctx).colorScheme.error
                    : Theme.of(ctx).colorScheme.onSurface,
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
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.only(
            left: RiffSpacing.xl,
            top: RiffSpacing.xs,
            right: RiffSpacing.xl,
            bottom: RiffSpacing.unit * 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song?.title ?? '', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: RiffSpacing.xs),
            Text(song?.artist ?? '', style: Theme.of(ctx).textTheme.titleSmall),
            const Divider(height: RiffSpacing.xxl),
            Text(
              notes.isEmpty ? "noShownotes".tr : notes,
              style: Theme.of(ctx).textTheme.bodyLarge,
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
      color: Theme.of(context).colorScheme.onSurface,
    ),
    iconSize: 42,
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
            borderRadius: BorderRadius.circular(RiffRadii.sm),
            border: Border.all(
                color: theme.colorScheme.error.withOpacity(0.35), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.only(
                left: RiffSpacing.md,
                top: RiffSpacing.sm,
                right: RiffSpacing.xs,
                bottom: RiffSpacing.sm),
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
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurface),
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
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: color),
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
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
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
                        size: RiffComponentSizes.trailingIcon,
                        semanticLabel: a.tooltip,
                        color: a.active ? accent : scheme.onSurfaceVariant,
                      ),
                      if (a.active && (a.badge ?? '').isNotEmpty)
                        Text(
                          a.badge!,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: accent),
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

/// Raised circle behind the title-row buttons (song options, like).
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Shuffle / repeat: accent with an accent dot when on, text colour when off.
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
          Icon(icon, size: 22, color: on ? accent : color),
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
    final theme = Theme.of(context);
    final titleStyle = RiffTextStyles.of(context).playerTitle;
    final artistStyle = theme.textTheme.bodyLarge
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final mask = RiffColors.of(context).onImage;
    return ShaderMask(
      // Fade the right edge so a scrolling title doesn't hard-clip.
      shaderCallback: (rect) => LinearGradient(
        colors: [mask, mask, Colors.transparent],
        stops: const [0, 0.9, 1],
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
                      style: titleStyle,
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
                      style: artistStyle,
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
              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
              : Theme.of(context).colorScheme.onSurface,
        ),
        iconSize: 42,
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

  /// Finger down on the bar: the thumb shows only then.
  bool _dragging = false;
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
      _dragging = true;
      _dragFrac = f;
      _dragPosition = pos;
    });
  }

  /// Seeks once and keeps the thumb at the target until the player reports
  /// a position near it (or a short timeout), so it doesn't snap back to the
  /// pre-seek position for a few ticks.
  void _commitScrub(PlayerController c) {
    if (_dragging) setState(() => _dragging = false);
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
    if (_dragFrac == null && _dragPosition == null && !_dragging) return;
    setState(() {
      _dragging = false;
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
      // Podcast segments as coloured spans on the track.
      final spans = totalMs <= 0
          ? const <(double, double, Color)>[]
          : [
              for (final s in controller.podcastSegments)
                (
                  (s.start * 1000 / totalMs).clamp(0.0, 1.0),
                  (s.end * 1000 / totalMs).clamp(0.0, 1.0),
                  s.category.color,
                )
            ];
      final theme = Theme.of(context);
      final timeStyle = theme.textTheme.labelSmall!
          .copyWith(color: theme.colorScheme.onSurfaceVariant);
      final currentLabel = _fmtDuration(_dragPosition ?? status.current);
      final totalLabel = _fmtDuration(status.total, allowZero: false);
      final played = theme.colorScheme.secondary;
      final rest = theme.colorScheme.outlineVariant;

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
                      spans: spans,
                      playedColor: played,
                      restColor: rest,
                      thumbColor: played,
                      showThumb: _dragging,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: RiffSpacing.xxs),
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
/// punch a gap so each section reads as its own pill. The thumb is drawn
/// only while [showThumb] (the user is dragging).
class _SectionTrackPainter extends CustomPainter {
  _SectionTrackPainter({
    required this.progress,
    required this.marks,
    required this.playedColor,
    required this.restColor,
    required this.thumbColor,
    required this.showThumb,
    this.spans = const [],
  });

  final double progress;
  final List<double> marks;

  /// Podcast segments: (start, end) as fractions, and their colour.
  final List<(double, double, Color)> spans;
  final Color playedColor;
  final Color restColor;
  final Color thumbColor;
  final bool showThumb;

  static const _gap = 3.0;
  static const _trackH = RiffComponentSizes.seekTrack;
  static const _thumb = RiffComponentSizes.seekThumb;
  static const _round = Radius.circular(RiffRadii.pill);

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
      final rect = RRect.fromLTRBR(left, top, right, top + _trackH, _round);
      canvas.drawRRect(rect, Paint()..color = restColor);
      final playedRight = (size.width * progress).clamp(left, right);
      if (playedRight > left + 0.5) {
        canvas.drawRRect(
          RRect.fromLTRBR(left, top, playedRight, top + _trackH, _round),
          Paint()..color = playedColor,
        );
      }
    }
    for (final (a, b, color) in spans) {
      final l = a * size.width, r = b * size.width;
      if (r - l < 1) continue;
      canvas.drawRRect(
        RRect.fromLTRBR(l, top, r, top + _trackH, _round),
        Paint()..color = color.withOpacity(0.9),
      );
    }
    if (!showThumb) return;
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
      old.showThumb != showThumb ||
      !_listEq(old.marks, marks) ||
      old.spans.length != spans.length ||
      !_spansEq(old.spans, spans);

  bool _spansEq(
      List<(double, double, Color)> a, List<(double, double, Color)> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
