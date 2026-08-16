import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ionicons/ionicons.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/ui/player/components/animated_play_button.dart';
import '/ui/player/components/podcast_transcript_sheet.dart';
import '/ui/utils/theme_controller.dart';
import '../../screens/Settings/settings_screen_controller.dart';
import '../../widgets/add_to_playlist.dart';
import '../../widgets/discovery/player_similar_row.dart';
import '../../widgets/favorite_heart_button.dart';
import '../player_controller.dart';
import '../player_media_nav.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                    ).createShader(
                        Rect.fromLTWH(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Obx(() {
                    final song = playerController.currentSong.value;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>(song?.id ?? 'none'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => openCurrentAlbum(playerController),
                            child: Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 10),
                              id: "${song}_title",
                              child: Text(
                                (song != null && song.title.isNotEmpty)
                                    ? song.title
                                    : "—",
                                textAlign: TextAlign.start,
                                style: Theme.of(context).textTheme.labelMedium!,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => openCurrentArtist(playerController),
                            child: Marquee(
                              delay: const Duration(milliseconds: 300),
                              duration: const Duration(seconds: 10),
                              id: "${song}_subtitle",
                              child: Text(
                                (song?.artist != null &&
                                        song!.artist!.isNotEmpty)
                                    ? song.artist!
                                    : "—",
                                textAlign: TextAlign.start,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          )
                        ],
                      ),
                    );
                  }),
                ),
              ),
              FavoriteHeartButton(
                isFav: playerController.isCurrentSongFav,
                onToggleFav: playerController.toggleFavourite,
                song: () => playerController.currentSong.value,
              ),
              IconButton(
                tooltip: 'addToPlaylist'.tr,
                icon: Icon(
                  Icons.playlist_add,
                  color: Theme.of(context).textTheme.titleMedium?.color,
                ),
                onPressed: () {
                  final song = playerController.currentSong.value;
                  if (song == null) return;
                  showAddToPlaylistSheet(context, [song]);
                },
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          // Shownotes / chapters / transcript / autoplay — tools row above
          // the seek bar. Autoplay lives here (not in the transport row) so
          // speed · −10 · play · +30 · next stays visually mirrored.
          Obx(() {
            if (!playerController.isCurrentSongPodcast) {
              return const SizedBox.shrink();
            }
            final song = playerController.currentSong.value;
            final transcriptUrl =
                (song?.extras?['transcriptUrl'] ?? '').toString();
            final settings = Get.find<SettingsScreenController>();
            final autoOn = settings.podcastContinuousPlaybackEnabled.value;
            final style = OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              side: BorderSide(
                  color: Theme.of(context)
                      .textTheme
                      .titleLarge!
                      .color!
                      .withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            );
            final autoStyle = OutlinedButton.styleFrom(
              foregroundColor: autoOn
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).textTheme.titleMedium!.color,
              side: BorderSide(
                color: autoOn
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context)
                        .textTheme
                        .titleLarge!
                        .color!
                        .withOpacity(0.4),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        settings.togglePodcastContinuousPlayback(!autoOn),
                    icon: Icon(
                      autoOn
                          ? Icons.playlist_play_rounded
                          : Icons.playlist_remove_rounded,
                      size: 20,
                    ),
                    label: Text(autoOn ? 'auto'.tr : 'stop'.tr),
                    style: autoStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openShownotes(playerController, context),
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: Text("shownotes".tr),
                    style: style,
                  ),
                  if (playerController.hasChapters)
                    OutlinedButton.icon(
                      onPressed: () => _openChapters(playerController, context),
                      icon: const Icon(Icons.list_rounded, size: 20),
                      label: Text("chapters".tr),
                      style: style,
                    ),
                  if (transcriptUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => PodcastTranscriptSheet.open(
                        context,
                        url: transcriptUrl,
                        type: '${song?.extras?['transcriptType'] ?? ''}',
                      ),
                      icon: const Icon(Icons.subtitles_outlined, size: 20),
                      label: Text("transcript".tr),
                      style: style,
                    ),
                ],
              ),
            );
          }),
          // Visible reason when a song won't start — snackbar alone is easy to miss.
          Obx(() {
            final err = playerController.playbackError.value;
            if (err == null || err.isEmpty) return const SizedBox.shrink();
            final theme = Theme.of(context);
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Material(
                color: theme.colorScheme.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          err,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.titleMedium?.color,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: playerController.retryPlayback,
                        child: Text("retry".tr),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // The seek control IS the SoundCloud-style waveform (no separate
          // slider line): it fills with the accent colour as the track plays,
          // shows the elapsed/total time beneath, and is tap/drag seekable.
          const _WaveformScrubber(),
          Obx(() => playerController.usesLongFormTransport
              ? _podcastControls(playerController, context)
              : _musicControls(playerController, context)),
          _nowPlayingActions(playerController, context),
          // Similar songs are music-only; hide for podcasts and audiobooks.
          Obx(() => playerController.usesLongFormTransport
              ? const SizedBox.shrink()
              : const PlayerSimilarRow()),
        ]);
  }

  /// Compact Radio / Play-next row under transport. Hidden on short screens
  /// and for podcasts/audiobooks so the panel does not overflow.
  Widget _nowPlayingActions(
      PlayerController playerController, BuildContext context) {
    return Obx(() {
      if (playerController.usesLongFormTransport) {
        return const SizedBox.shrink();
      }
      final song = playerController.currentSong.value;
      if (song == null) return const SizedBox.shrink();
      final size = MediaQuery.sizeOf(context);
      // Hide on landscape / very short viewports; portrait phones keep the row
      // and Wrap handles narrow widths.
      if (size.height < 560) return const SizedBox.shrink();

      final labelStyle = Theme.of(context).textTheme.labelSmall;
      final color = Theme.of(context).textTheme.titleMedium?.color;
      final style = TextButton.styleFrom(
        foregroundColor: color,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
      );

      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 0,
          children: [
            TextButton.icon(
              onPressed: () => playerController.startRadio(song),
              icon: const Icon(Icons.sensors, size: 18),
              label: Text("startRadio".tr, style: labelStyle),
              style: style,
            ),
            TextButton.icon(
              onPressed: () => playerController.moreLikeThisPlayNext(song),
              icon: const Icon(Icons.playlist_play, size: 18),
              label: Text("playNext".tr, style: labelStyle),
              style: style,
            ),
          ],
        ),
      );
    });
  }

  Widget _musicControls(
      PlayerController playerController, BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
            onPressed: playerController.toggleShuffleMode,
            icon: Obx(() => Icon(
                  Ionicons.shuffle,
                  color: playerController.isShuffleModeEnabled.value
                      ? RiffSurfaces.textPrimary
                      : RiffSurfaces.textMuted.withOpacity(0.45),
                ))),
        _previousButton(playerController, context),
        const AnimatedPlayButton(key: Key("playButton")),
        _nextButton(playerController, context),
        Obx(() {
          final state = playerController.repeatState;
          return IconButton(
              tooltip: state == 2
                  ? "repeatOne".tr
                  : state == 1
                      ? "repeatAll".tr
                      : "repeat".tr,
              onPressed: playerController.cycleRepeatMode,
              icon: Icon(
                // repeat_one shows the "1" badge (Spotify-style).
                state == 2 ? Icons.repeat_one : Icons.repeat,
                color: state == 0
                    ? RiffSurfaces.textMuted.withOpacity(0.45)
                    : RiffSurfaces.textPrimary,
              ));
        }),
      ],
    );
  }

  /// AntennaPod-style transport: speed · −10s · play/pause · +30s · next.
  /// (Autoplay is in the tools row above so this bar stays mirrored.)
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
        _podcastButtonsRow(playerController, context, color),
      ],
    );
  }

  Widget _podcastButtonsRow(
      PlayerController playerController, BuildContext context, Color? color) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    // Five equal columns around a fixed play button keep left/right mirrored.
    Widget side({required Widget child}) => Expanded(child: child);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        side(child: _SpeedButton(color: color)),
        side(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 32,
                onPressed: () =>
                    playerController.seekBy(const Duration(seconds: -10)),
                icon: Icon(Icons.replay_10, color: color),
              ),
              Text('10', style: labelStyle),
            ],
          ),
        ),
        const AnimatedPlayButton(key: Key('podcastPlayButton')),
        side(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 32,
                onPressed: () =>
                    playerController.seekBy(const Duration(seconds: 30)),
                icon: Icon(Icons.forward_30, color: color),
              ),
              Text('30', style: labelStyle),
            ],
          ),
        ),
        side(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _nextButton(playerController, context),
              // Reserve the same caption line as Speed / 10 / 30.
              Text(
                ' ',
                style: labelStyle,
                strutStyle: StrutStyle(
                  forceStrutHeight: true,
                  fontSize: labelStyle?.fontSize ?? 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openChapters(PlayerController playerController, BuildContext context) {
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

  void _openShownotes(PlayerController playerController, BuildContext context) {
    final song = playerController.currentSong.value;
    final notes = (song?.extras?['description'] ?? '').toString().trim();
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
              Text(song?.title ?? '',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(song?.artist ?? '',
                  style: Theme.of(ctx).textTheme.titleSmall),
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
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      iconSize: 30,
      onPressed: playerController.prev,
    );
  }
}

/// Podcast playback-speed control: shows the current speed, tap cycles through
/// common podcast speeds. Persists via SettingsScreenController like the
/// speed/pitch dialog.
class _SpeedButton extends StatelessWidget {
  const _SpeedButton({required this.color});
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 30,
          onPressed: _cycle,
          icon: Icon(Icons.speed, color: color),
        ),
        Obx(() => Text(
              settings.playbackSpeed.value.toStringAsFixed(2),
              style: Theme.of(context).textTheme.labelSmall,
            )),
      ],
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final isLastSong = playerController.currentQueue.isEmpty ||
        (!(playerController.isShuffleModeEnabled.isTrue ||
                playerController.isQueueLoopModeEnabled.isTrue) &&
            (playerController.currentQueue.last.id ==
                playerController.currentSong.value?.id));
    return IconButton(
        icon: Icon(
          Icons.skip_next,
          color: isLastSong
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: isLastSong ? null : playerController.next);
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

/// Waveform seek bar with local drag preview so scrubbing stays snappy even
/// when progress UI updates are throttled upstream.
class _WaveformScrubber extends StatefulWidget {
  const _WaveformScrubber();

  @override
  State<_WaveformScrubber> createState() => _WaveformScrubberState();
}

class _WaveformScrubberState extends State<_WaveformScrubber> {
  double? _dragFrac;
  Duration? _dragPosition;

  void _scrubTo(double dx, double width, Duration total, PlayerController c) {
    if (total.inMilliseconds <= 0 || width <= 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    final pos = total * f;
    setState(() {
      _dragFrac = f;
      _dragPosition = pos;
    });
    c.seek(pos);
  }

  void _endScrub() {
    if (_dragFrac == null && _dragPosition == null) return;
    setState(() {
      _dragFrac = null;
      _dragPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(builder: (controller) {
      final status = controller.progressBarStatus.value;
      final totalMs = status.total.inMilliseconds;
      final liveFrac = totalMs > 0
          ? (status.current.inMilliseconds / totalMs).clamp(0.0, 1.0)
          : 0.0;
      final frac = _dragFrac ?? liveFrac;
      final song = controller.currentSong.value;
      final seed = (song?.id ?? song?.title ?? '').hashCode;
      final timeStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: 12,
            color: RiffSurfaces.textMuted,
            fontWeight: FontWeight.w500,
          );
      final currentLabel = _fmtDuration(_dragPosition ?? status.current);
      final totalLabel = _fmtDuration(status.total, allowZero: false);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total, controller),
                onTapUp: (_) => _endScrub(),
                onTapCancel: _endScrub,
                onHorizontalDragStart: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total, controller),
                onHorizontalDragUpdate: (d) =>
                    _scrubTo(d.localPosition.dx, width, status.total, controller),
                onHorizontalDragEnd: (_) => _endScrub(),
                onHorizontalDragCancel: _endScrub,
                child: SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      progress: frac,
                      seed: seed,
                      playedColor: Theme.of(context)
                              .sliderTheme
                              .activeTrackColor ??
                          Theme.of(context).colorScheme.secondary,
                      unplayedColor: (Theme.of(context)
                                  .sliderTheme
                                  .inactiveTrackColor ??
                              RiffSurfaces.hairline)
                          .withOpacity(0.55),
                      playheadColor: RiffSurfaces.textPrimary,
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

/// A thin SoundCloud-style waveform. Bar heights are deterministic per song
/// (hashed from a seed) so they stay stable across rebuilds; the played portion
/// is drawn in [playedColor], the rest in [unplayedColor]. A thin playhead
/// line marks the current position.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.seed,
    required this.playedColor,
    required this.unplayedColor,
    required this.playheadColor,
  });

  final double progress; // 0..1
  final int seed;
  final Color playedColor;
  final Color unplayedColor;
  final Color playheadColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.5;
    const gap = 1.5;
    const step = barWidth + gap;
    final count = (size.width / step).floor();
    if (count <= 0) return;
    final midY = size.height / 2;
    final playedBars = (count * progress).round();
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    for (int i = 0; i < count; i++) {
      // Deterministic pseudo-random amplitude in [0.30, 1.0].
      final n = (seed ^ (i * 2654435761)) & 0x7fffffff;
      final amp = 0.30 + (n % 1000) / 1000.0 * 0.70;
      final barH = size.height * amp;
      final x = i * step + barWidth / 2;
      paint.color = i < playedBars ? playedColor : unplayedColor;
      canvas.drawLine(
          Offset(x, midY - barH / 2), Offset(x, midY + barH / 2), paint);
    }
    // Playhead line at the current progress position.
    final playheadX = (size.width * progress).clamp(0.0, size.width);
    final head = Paint()
      ..color = playheadColor.withOpacity(0.9)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(playheadX, 2), Offset(playheadX, size.height - 2), head);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor ||
      old.playheadColor != playheadColor;
}
