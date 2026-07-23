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
import 'add_to_playlist.dart';
import 'image_widget.dart';
import 'snackbar.dart';
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

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Listener(
        onPointerDown: (PointerDownEvent event) {
          if (event.buttons == kSecondaryMouseButton) {
            //show songinfobotomsheet
            showModalBottomSheet(
              constraints: const BoxConstraints(maxWidth: 500),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
              ),
              isScrollControlled: true,
              context: playerController.homeScaffoldkey.currentState!.context,
              barrierColor: Colors.transparent.withAlpha(100),
              builder: (context) => SongInfoBottomSheet(
                song,
                playlist: playlist,
              ),
            ).whenComplete(() => Get.delete<SongInfoController>());
          }
        },
        child: Slidable(
          enabled:
              Get.find<SettingsScreenController>().slidableActionEnabled.isTrue,
          startActionPane: ActionPane(motion: const DrawerMotion(), children: [
            SlidableAction(
              onPressed: (context) {
                showDialog(
                  context: context,
                  builder: (context) => AddToPlaylist([song]),
                ).whenComplete(() => Get.delete<AddToPlaylistController>());
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
          child: ListTile(
            onTap: onTap,
            onLongPress: () async {
              showModalBottomSheet(
                constraints: const BoxConstraints(maxWidth: 500),
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16.0)),
                ),
                isScrollControlled: true,
                context: playerController.homeScaffoldkey.currentState!.context,
                //constraints: BoxConstraints(maxHeight:Get.height),
                barrierColor: Colors.transparent.withAlpha(100),
                builder: (context) => SongInfoBottomSheet(
                  song,
                  playlist: playlist,
                ),
              ).whenComplete(() => Get.delete<SongInfoController>());
            },
            contentPadding:
                const EdgeInsets.only(top: 0, left: 8, right: 16, bottom: 0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: thumbReplacementWithIndex
                ? SizedBox(
                    width: 27.5,
                    height: 52,
                    child: Center(
                      child: Text(
                        "$index.",
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                : ImageWidget(
                    size: 52,
                    song: song,
                  ),
            title: Marquee(
              delay: const Duration(milliseconds: 300),
              duration: const Duration(seconds: 5),
              id: song.title.hashCode.toString(),
              child: Text(
                song.title.length > 50
                    ? song.title.substring(0, 50)
                    : song.title,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                    ),
              ),
            ),
            subtitle: Text(
              "${song.artist}",
              maxLines: 1,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            trailing: SizedBox(
              width: showMixMeta
                  ? (Get.size.width > 800 ? 168 : 132)
                  : (Get.size.width > 800 ? 80 : 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showMixMeta) ...[
                    _MixMetaColumn(analysis: mixAnalysis),
                    const SizedBox(width: 6),
                  ],
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPlaylistOrAlbum)
                        Obx(() =>
                            playerController.currentSong.value?.id == song.id
                                ? const Icon(
                                    Icons.equalizer,
                                  )
                                : const SizedBox.shrink()),
                      Text(
                        song.extras!['length'] ?? "",
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  if (GetPlatform.isDesktop)
                    IconButton(
                        splashRadius: 20,
                        onPressed: () {
                          showModalBottomSheet(
                            constraints: const BoxConstraints(maxWidth: 500),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10.0)),
                            ),
                            isScrollControlled: true,
                            context: playerController
                                .homeScaffoldkey.currentState!.context,
                            //constraints: BoxConstraints(maxHeight:Get.height),
                            barrierColor: Colors.transparent.withAlpha(100),
                            builder: (context) => SongInfoBottomSheet(
                              song,
                              playlist: playlist,
                            ),
                          ).whenComplete(
                              () => Get.delete<SongInfoController>());
                        },
                        icon: const Icon(Icons.more_vert))
                ],
              ),
            ),
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
            borderRadius: BorderRadius.circular(6),
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
