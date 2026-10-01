import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/piped_service.dart';
import '../screens/Library/library_controller.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/widgets/snackbar.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'riff_sheet.dart';
import '../screens/Home/home_layout.dart';
import '../utils/riff_tokens.dart';
import '../utils/theme_controller.dart';

class CreateNRenamePlaylistPopup extends StatelessWidget {
  const CreateNRenamePlaylistPopup(
      {super.key,
      this.isCreateNadd = false,
      this.songItems,
      this.renamePlaylist = false,
      this.playlist});
  final bool isCreateNadd;
  final bool renamePlaylist;
  final List<MediaItem>? songItems;
  final Playlist? playlist;

  Future<void> _submit(
      BuildContext context, LibraryPlaylistsController librPlstCntrller) async {
    if (librPlstCntrller.textInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context, "playlistNameRequired".tr,
          size: SanckBarSize.MEDIUM));
      return;
    }
    if (renamePlaylist) {
      final value = await librPlstCntrller.renamePlaylist(playlist!);
      if (!context.mounted) return;
      if (value) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "playlistRenameAlert".tr,
            size: SanckBarSize.MEDIUM));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
            context, "operationFailed".tr,
            size: SanckBarSize.MEDIUM));
      }
      return;
    }
    final value = await librPlstCntrller.createNewPlaylist(
        createPlaylistNaddSong: isCreateNadd, songItems: songItems);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        value
            ? (isCreateNadd
                ? "playlistCreatednsongAddedAlert".tr
                : "playlistCreatedAlert".tr)
            : "errorOccuredAlert".tr,
        size: SanckBarSize.MEDIUM));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final librPlstCntrller = Get.find<LibraryPlaylistsController>();
    librPlstCntrller.changeCreationMode("local");
    librPlstCntrller.textInputController.text = renamePlaylist
        ? ""
        : defaultNewPlaylistName(songItems: songItems);
    final isPipedLinked = Get.find<PipedServices>().isLoggedIn;
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    renamePlaylist ? "renamePlaylist".tr : "CreateNewPlaylist".tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: fg),
                  ),
                ),
                Obx(() => (librPlstCntrller.creationInProgress.isTrue &&
                        isPipedLinked)
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 14),
            if (isPipedLinked && !renamePlaylist) ...[
              Obx(() {
                final mode = librPlstCntrller.playlistCreationMode.value;
                return Row(
                  children: [
                    RiffChoiceChip(
                      icon: Icons.phone_android_rounded,
                      label: "local".tr,
                      selected: mode == "local",
                      onTap: () => librPlstCntrller.changeCreationMode("local"),
                    ),
                    const SizedBox(width: 8),
                    RiffChoiceChip(
                      icon: Icons.cloud_outlined,
                      label: "Piped".tr,
                      selected: mode == "piped",
                      onTap: () => librPlstCntrller.changeCreationMode("piped"),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 14),
            ],
            ModifiedTextField(
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              cursorColor: theme.colorScheme.secondary,
              controller: librPlstCntrller.textInputController,
              onSubmitted: (_) => _submit(context, librPlstCntrller),
              decoration: InputDecoration(
                hintText: "playlistName".tr,
                filled: true,
                fillColor: homeTileColor(context),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                  borderSide:
                      BorderSide(color: theme.colorScheme.secondary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: Text("cancel".tr,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _submit(context, librPlstCntrller),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondary,
                    foregroundColor: RiffSurfaces.voidBlack,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: Text(
                    isCreateNadd
                        ? "createnAdd".tr
                        : renamePlaylist
                            ? "rename".tr
                            : "create".tr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
