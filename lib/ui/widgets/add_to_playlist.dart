import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../services/piped_service.dart';
import '../utils/riff_tokens.dart';
import '/models/media_Item_builder.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'image_widget.dart';
import 'snackbar.dart';

class AddToPlaylist extends StatelessWidget {
  const AddToPlaylist(this.songItems, {super.key});
  final List<MediaItem> songItems;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(AddToPlaylistController());
    final isPipedLinked = Get.find<PipedServices>().isLoggedIn;
    final theme = Theme.of(context);

    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + inline "New" create action.
            Row(
              children: [
                Expanded(
                  child: Text(
                    "addToPlaylist".tr,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder: (context) => CreateNRenamePlaylistPopup(
                          isCreateNadd: true, songItems: songItems),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text("newPlaylistShort".tr),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ),
            // Piped / local source toggle (only when a Piped account is linked).
            if (isPipedLinked) ...[
              const SizedBox(height: 12),
              Obx(() => SegmentedButton<String>(
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: [
                      ButtonSegment(
                          value: "local",
                          label: Text("local".tr),
                          icon: const Icon(Icons.phone_android, size: 16)),
                      ButtonSegment(
                          value: "piped",
                          label: Text("Piped".tr),
                          icon: const Icon(Icons.cloud_outlined, size: 16)),
                    ],
                    selected: {controller.playlistType.value},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        controller.changePlaylistType(s.first),
                  )),
            ],
            const SizedBox(height: 12),
            // Playlist list — flexible height so the last row is never clipped.
            Flexible(
              child: Obx(() {
                if (controller.additionInProgress.value) {
                  return const SizedBox(
                    height: 120,
                    child: Center(
                      child: SizedBox(
                        height: 26,
                        width: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  );
                }
                if (controller.playlists.isEmpty) {
                  return _EmptyPlaylists(theme: theme);
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                  child: Material(
                    color: theme.primaryColorLight.withOpacity(0.35),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: controller.playlists.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: RiffTokens.hairline,
                        indent: 68,
                        color: theme.dividerColor.withOpacity(0.25),
                      ),
                      itemBuilder: (context, index) => _PlaylistRow(
                        playlist: controller.playlists[index],
                        onTap: () => _onPick(context, controller, index),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _onPick(BuildContext context, AddToPlaylistController controller,
      int index) {
    controller
        .addSongsToPlaylist(
            songItems, controller.playlists[index].playlistId, context)
        .then((added) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          added ? "songAddedToPlaylistAlert".tr : "songAlreadyExists".tr,
          size: SanckBarSize.MEDIUM));
      Navigator.of(context).pop();
    });
  }
}

/// One playlist row: rounded cover art, title, and song count when known.
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});
  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = playlist.songCount;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
              child: ImageWidget(size: 44, playlist: playlist),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (count != null && count.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      "$count ${'songs'.tr}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.add, size: 22, color: theme.colorScheme.secondary),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dim = theme.textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_add, size: 48, color: dim?.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            "noLibPlaylist".tr,
            textAlign: TextAlign.center,
            style:
                theme.textTheme.bodyMedium?.copyWith(color: dim?.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

class AddToPlaylistController extends GetxController {
  final RxList<Playlist> playlists = RxList();
  final playlistType = "local".obs;
  final additionInProgress = false.obs;
  List<Playlist> localPlaylists = [];
  List<Playlist> pipedPlaylists = [];
  AddToPlaylistController() {
    _getAllPlaylist();
  }

  Future<void> _getAllPlaylist() async {
    final plstsBox = await Hive.openBox("LibraryPlaylists");
    playlists.value = plstsBox.values
        .map((e) {
          if (!e["isCloudPlaylist"]) return Playlist.fromJson(e);
        })
        .whereType<Playlist>()
        .toList();
    localPlaylists = playlists.toList();
    final res = await Get.find<PipedServices>().getAllPlaylists();
    if (res.code == 1) {
      pipedPlaylists = res.response
          .map((item) => Playlist(
                title: item['name'],
                playlistId: item['id'],
                description: "Piped Playlist",
                thumbnailUrl: item['thumbnail'],
                isPipedPlaylist: true,
              ))
          .whereType<Playlist>()
          .toList();
    }
  }

  void changePlaylistType(val) {
    playlistType.value = val;
    playlists.value = val == "piped" ? pipedPlaylists : localPlaylists;
  }

  Future<bool> addSongsToPlaylist(
      List<MediaItem> songs, String playlistId, BuildContext context) async {
    additionInProgress.value = true;
    if (playlistType.value == "local") {
      final plstBox = await Hive.openBox(playlistId);
      final playlistSongIds = plstBox.values.map((item) => item['videoId']);
      for (MediaItem element in songs) {
        if (!playlistSongIds.contains(element.id)) {
          await plstBox.add(MediaItemBuilder.toJson(element));
        }
      }
      await plstBox.close();
      additionInProgress.value = false;
      return true;
    } else {
      final videosId = songs.map((e) => e.id).toList();
      final res =
          await Get.find<PipedServices>().addToPlaylist(playlistId, videosId);
      additionInProgress.value = false;
      return (res.code == 1);
    }
  }

  // Future<bool> addSongToPlaylist(
  //     MediaItem song, String playlistId, BuildContext context) async {
  //   if (playlistType.value == "local") {
  //     final plstBox = await Hive.openBox(playlistId);
  //     if (!plstBox.containsKey(song.id)) {
  //       plstBox.put(song.id, MediaItemBuilder.toJson(song));
  //       plstBox.close();
  //       return true;
  //     } else {
  //       plstBox.close();
  //       return false;
  //     }
  //   } else {
  //     additionInProgress.value = true;

  //     final res =
  //         await Get.find<PipedServices>().addToPlaylist(playlistId, song.id);
  //     additionInProgress.value = false;
  //     return (res.code == 1);
  //   }
  // }
}
