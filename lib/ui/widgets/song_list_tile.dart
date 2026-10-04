import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '../../models/playlist.dart';
import '../../services/track_analysis_service.dart';
import '../player/player_controller.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/theme/riff_spacing.dart';
import 'add_to_playlist.dart';
import 'image_widget.dart';
import 'riff_sheet.dart';
import 'snackbar.dart';
import 'song_favourite.dart';
import 'songinfo_bottom_sheet.dart';

class SongListTile extends StatelessWidget with RemoveSongFromPlaylistMixin {
  const SongListTile(
      {super.key,
      this.onTap,
      required this.song,
      this.playlist,
      this.isPlaylistOrAlbum = false,
      this.thumbReplacementWithIndex = false,
      this.index,
      this.mixAnalysis,
      this.showMixMeta = false,
      this.fullWidthHairline = false});
  final Playlist? playlist;
  final MediaItem song;
  final VoidCallback? onTap;
  final bool isPlaylistOrAlbum;

  /// Valid for Album songs
  final bool thumbReplacementWithIndex;
  final int? index;

  /// When Mix mode is on, optional BPM / Camelot from TrackAnalysisService.
  final TrackAnalysis? mixAnalysis;
  final bool showMixMeta;

  /// Search results draw a full-width hairline; track lists (album,
  /// playlist, library) an inset one starting at the text (§5.2).
  final bool fullWidthHairline;

  void _openSheet(PlayerController playerController) {
    final sheetContext =
        playerController.homeScaffoldkey.currentContext ?? Get.context;
    if (sheetContext == null) return;
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: riffSheetShape,
      isScrollControlled: true,
      useRootNavigator: true,
      context: sheetContext,
      barrierColor: RiffColors.of(sheetContext).scrim.withAlpha(100),
      builder: (context) => SongInfoBottomSheet(
        song,
        playlist: playlist,
      ),
    ).whenComplete(() => Get.delete<SongInfoController>());
  }

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.secondary;
    final muted = scheme.onSurfaceVariant;
    final nowPlayingTint = RiffColors.of(context).accentMuted;
    final slideBg = scheme.secondary;
    final slideFg = scheme.onSecondary;

    return Listener(
        onPointerDown: (PointerDownEvent event) {
          if (event.buttons == kSecondaryMouseButton) {
            _openSheet(playerController);
          }
        },
        child: Slidable(
          enabled:
              Get.find<SettingsScreenController>().slidableActionEnabled.isTrue,
          startActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) {
                showAddToPlaylistSheet(context, [song]);
              },
              backgroundColor: slideBg,
              foregroundColor: slideFg,
              icon: Icons.playlist_add,
              //label: 'Add to playlist',
            ),
            if (playlist != null && !playlist!.isCloudPlaylist)
              SlidableAction(
                onPressed: (context) {
                  removeSongFromPlaylist(song, playlist!);
                },
                backgroundColor: slideBg,
                foregroundColor: slideFg,
                icon: Icons.delete,
                //label: 'delete',
              ),
          ]),
          endActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) async {
                final ok = await playerController.enqueueSong(song);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context, ok ? "songEnqueueAlert".tr : "operationFailed".tr,
                    size: SanckBarSize.MEDIUM));
              },
              backgroundColor: slideBg,
              foregroundColor: slideFg,
              icon: Icons.merge,
              //label: 'Enqueue',
            ),
            SlidableAction(
              onPressed: (context) async {
                final ok = await playerController.playNext(song);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context,
                    ok
                        ? "${"playnextMsg".tr} ${(song).title}"
                        : "operationFailed".tr,
                    size: SanckBarSize.BIG));
              },
              backgroundColor: slideBg,
              foregroundColor: slideFg,
              icon: Icons.next_plan_outlined,
              //label: 'Play Next',
            ),
          ]),
          // Art / Marquee stay outside Obx so current-song ticks only rebuild
          // the highlight chrome + equalizer, not image decode / marquee state.
          child: Stack(
            children: [
              Positioned.fill(
                child: Obx(() {
                  final isCurrent =
                      playerController.currentSong.value?.id == song.id;
                  // Flat accentMuted tint for the now-playing row (§5.2).
                  return IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isCurrent ? nowPlayingTint : null,
                      ),
                    ),
                  );
                }),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: () => _openSheet(playerController),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: RiffSpacing.lg, vertical: RiffSpacing.md),
                    child: Row(
                      children: [
                        thumbReplacementWithIndex
                            ? SizedBox(
                                width: RiffComponentSizes.rowArt,
                                height: RiffComponentSizes.rowArt,
                                child: Center(
                                  child: Text(
                                    "$index.",
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              )
                            : ImageWidget(
                                size: RiffComponentSizes.rowArt,
                                song: song,
                                borderRadius: RiffRadii.xs,
                              ),
                        const SizedBox(width: RiffSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Marquee(
                                delay: const Duration(milliseconds: 300),
                                duration: const Duration(seconds: 5),
                                id: song.title.hashCode.toString(),
                                child: Obx(() {
                                  final isCurrent =
                                      playerController.currentSong.value?.id ==
                                          song.id;
                                  return Text(
                                    song.title.length > 50
                                        ? song.title.substring(0, 50)
                                        : song.title,
                                    maxLines: 1,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: isCurrent ? accent : null,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: RiffSpacing.xxs),
                              Text(
                                "${song.artist}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: RiffSpacing.sm),
                        if (showMixMeta) ...[
                          _MixMetaColumn(analysis: mixAnalysis),
                          const SizedBox(width: RiffSpacing.xs),
                        ],
                        Obx(() {
                          final isCurrent =
                              playerController.currentSong.value?.id == song.id;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isCurrent)
                                Icon(Icons.equalizer,
                                    color: accent,
                                    size: RiffComponentSizes.trailingIcon),
                              Text(
                                song.extras?['length'] ?? "",
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          );
                        }),
                        SongRowHeartButton(
                          song: song,
                          iconSize: RiffComponentSizes.trailingIcon,
                          color: muted,
                        ),
                        IconButton(
                          iconSize: RiffComponentSizes.trailingIcon,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: RiffComponentSizes.rowIconHit,
                            minHeight: RiffComponentSizes.rowIconHit,
                          ),
                          splashRadius: RiffComponentSizes.rowIconHit / 2,
                          onPressed: () => _openSheet(playerController),
                          icon: Icon(
                            Icons.more_vert,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Hairline inside the row's bottom edge; the inset one starts
              // at the text column (art and index slot are the same width).
              RiffRowHairline(
                  inset: fullWidthHairline ? 0 : RiffRowHairline.textInset),
            ],
          ),
        ));
  }
}

/// One-physical-pixel divider hairline drawn inside the bottom edge of a
/// row (§5.1 / §5.2) — a foreground layer in the row's [Stack], so it never
/// changes the row's extent. [inset] 0 = full width; [textInset] starts it
/// at the row's text column (gutter + 48 art + gap = 76).
class RiffRowHairline extends StatelessWidget {
  const RiffRowHairline({super.key, this.inset = 0});

  static const double textInset =
      RiffSpacing.lg + RiffComponentSizes.rowArt + RiffSpacing.md;

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      left: inset,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MixMetaColumn extends StatelessWidget {
  const _MixMetaColumn({this.analysis});
  final TrackAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bpm =
        analysis == null || analysis!.bpm <= 0 ? '—' : '${analysis!.bpm} bpm';
    final camelot =
        analysis?.camelot.isNotEmpty == true ? analysis!.camelot : '—';
    final keyColor = _camelotColor(camelot, theme);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          bpm,
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: RiffSpacing.xxs),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: RiffSpacing.xs, vertical: RiffSpacing.xxs),
          decoration: BoxDecoration(
            color: keyColor.withOpacity(0.22),
            borderRadius: BorderRadius.circular(RiffRadii.xs),
          ),
          child: Text(
            camelot,
            style: theme.textTheme.labelSmall?.copyWith(
              color: keyColor,
            ),
          ),
        ),
      ],
    );
  }

  Color _camelotColor(String camelot, ThemeData theme) {
    final m =
        RegExp(r'^(\d{1,2})([AB])$', caseSensitive: false).firstMatch(camelot);
    if (m == null) return theme.colorScheme.onSurface.withOpacity(0.5);
    final n = int.parse(m.group(1)!);
    final isA = m.group(2)!.toUpperCase() == 'A';
    // Distinct hues around the Camelot wheel.
    final hue = ((n - 1) * 30.0 + (isA ? 0 : 15)) % 360;
    return HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
  }
}
