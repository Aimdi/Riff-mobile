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
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
            snackbar(context, "operationFailed".tr, size: SanckBarSize.MEDIUM));
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
    librPlstCntrller.textInputController.text =
        renamePlaylist ? "" : defaultNewPlaylistName(songItems: songItems);
    final isPipedLinked = Get.find<PipedServices>().isLoggedIn;
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return CommonDialog(
      child: Padding(
        padding: const EdgeInsets.only(
            left: RiffSpacing.xxl,
            top: RiffSpacing.xxl,
            right: RiffSpacing.xxl,
            bottom: RiffSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    renamePlaylist
                        ? "renamePlaylist".tr
                        : "CreateNewPlaylist".tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(color: fg),
                  ),
                ),
                Obx(() => (librPlstCntrller.creationInProgress.isTrue &&
                        isPipedLinked)
                    ? const SizedBox(
                        height: RiffComponentSizes.spinner,
                        width: RiffComponentSizes.spinner,
                        child: CircularProgressIndicator(
                            strokeWidth: RiffComponentSizes.spinnerStroke))
                    : const SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: RiffSpacing.md),
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
                    const SizedBox(width: RiffSpacing.sm),
                    RiffChoiceChip(
                      icon: Icons.cloud_outlined,
                      label: "Piped".tr,
                      selected: mode == "piped",
                      onTap: () => librPlstCntrller.changeCreationMode("piped"),
                    ),
                  ],
                );
              }),
              const SizedBox(height: RiffSpacing.md),
            ],
            ModifiedTextField(
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              controller: librPlstCntrller.textInputController,
              onSubmitted: (_) => _submit(context, librPlstCntrller),
              // §5.8: transparent, hairline border radius 4, 2dp accent
              // when focused — all from the theme's input decoration.
              decoration: InputDecoration(
                hintText: "playlistName".tr,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: RiffSpacing.lg, vertical: RiffSpacing.md),
              ),
            ),
            const SizedBox(height: RiffSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("cancel".tr),
                ),
                const SizedBox(width: RiffSpacing.sm),
                FilledButton(
                  onPressed: () => _submit(context, librPlstCntrller),
                  child: Text(
                    isCreateNadd
                        ? "createnAdd".tr
                        : renamePlaylist
                            ? "rename".tr
                            : "create".tr,
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
