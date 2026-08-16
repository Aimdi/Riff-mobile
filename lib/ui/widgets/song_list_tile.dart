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
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';
import 'add_to_playlist.dart';
import 'image_widget.dart';
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
      this.showMixMeta = false});
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

  void _openSheet(PlayerController playerController) {
    final sheetContext =
        playerController.homeScaffoldkey.currentContext ?? Get.context;
    if (sheetContext == null) return;
    showModalBottomSheet(
      constraints: const BoxConstraints(maxWidth: 500),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(RiffTokens.radiusSm)),
      ),
      isScrollControlled: true,
      useRootNavigator: true,
      context: sheetContext,
      barrierColor: Colors.transparent.withAlpha(100),
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
    final accent = theme.colorScheme.secondary;
    final muted = theme.brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : theme.textTheme.titleSmall?.color?.withOpacity(0.65);
    final highlight = theme.brightness == Brightness.dark
        ? RiffSurfaces.elevatedSoft
        : accent.withOpacity(0.08);
    final radius = BorderRadius.circular(RiffTokens.radiusSm);

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
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.playlist_add,
              //label: 'Add to playlist',
            ),
            if (playlist != null && !playlist!.isCloudPlaylist)
              SlidableAction(
                onPressed: (context) {
                  removeSongFromPlaylist(song, playlist!);
                },
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
                icon: Icons.delete,
                //label: 'delete',
              ),
          ]),
          endActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) {
                playerController.enqueueSong(song).whenComplete(() {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(snackbar(
                      context, "songEnqueueAlert".tr,
                      size: SanckBarSize.MEDIUM));
                });
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
              icon: Icons.merge,
              //label: 'Enqueue',
            ),
            SlidableAction(
              onPressed: (context) {
                playerController.playNext(song);
                ScaffoldMessenger.of(context).showSnackBar(snackbar(
                    context, "${"playnextMsg".tr} ${(song).title}",
                    size: SanckBarSize.BIG));
              },
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
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
                  return IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isCurrent ? highlight : null,
                        borderRadius: radius,
                        // Soft elevated fill + thin secondary cue (not a thick rail).
                        border: isCurrent
                            ? Border(
                                left: BorderSide(color: accent, width: 2),
                              )
                            : null,
                      ),
                    ),
                  );
                }),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  onLongPress: () => _openSheet(playerController),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                    child: Row(
                      children: [
                        thumbReplacementWithIndex
                            ? SizedBox(
                                width: 27.5,
                                height: 52,
                                child: Center(
                                  child: Text(
                                    "$index.",
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              )
                            : ImageWidget(
                                size: 52,
                                song: song,
                                borderRadius: RiffTokens.radiusSm,
                              ),
                        const SizedBox(width: 10),
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
                                  final isCurrent = playerController
                                          .currentSong.value?.id ==
                                      song.id;
                                  return Text(
                                    song.title.length > 50
                                        ? song.title.substring(0, 50)
                                        : song.title,
                                    maxLines: 1,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.15,
                                      color: isCurrent ? accent : null,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${song.artist}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (showMixMeta) ...[
                          _MixMetaColumn(analysis: mixAnalysis),
                          const SizedBox(width: 6),
                        ],
                        Obx(() {
                          final isCurrent =
                              playerController.currentSong.value?.id ==
                                  song.id;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isCurrent)
                                Icon(Icons.equalizer,
                                    color: accent, size: 18),
                              Text(
                                song.extras?['length'] ?? "",
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ],
                          );
                        }),
                        IconButton(
                          tooltip: 'addToPlaylist'.tr,
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: 18,
                          onPressed: () =>
                              showAddToPlaylistSheet(context, [song]),
                          icon: Icon(
                            Icons.playlist_add,
                            color: muted,
                          ),
                        ),
                        SongRowHeartButton(
                          song: song,
                          iconSize: 20,
                          color: muted,
                        ),
                        if (GetPlatform.isDesktop)
                          IconButton(
                            splashRadius: 20,
                            onPressed: () => _openSheet(playerController),
                            icon: const Icon(Icons.more_vert),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }
}

class _MixMetaColumn extends StatelessWidget {
  const _MixMetaColumn({this.analysis});
  final TrackAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bpm = analysis == null || analysis!.bpm <= 0
        ? '—'
        : '${analysis!.bpm} bpm';
    final camelot = analysis?.camelot.isNotEmpty == true
        ? analysis!.camelot
        : '—';
    final keyColor = _camelotColor(camelot, theme);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          bpm,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: keyColor.withOpacity(0.22),
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm / 2),
          ),
          child: Text(
            camelot,
            style: theme.textTheme.labelSmall?.copyWith(
              color: keyColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Color _camelotColor(String camelot, ThemeData theme) {
    final m = RegExp(r'^(\d{1,2})([AB])$', caseSensitive: false)
        .firstMatch(camelot);
    if (m == null) return theme.colorScheme.onSurface.withOpacity(0.5);
    final n = int.parse(m.group(1)!);
    final isA = m.group(2)!.toUpperCase() == 'A';
    // Distinct hues around the Camelot wheel.
    final hue = ((n - 1) * 30.0 + (isA ? 0 : 15)) % 360;
    return HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
  }
}
