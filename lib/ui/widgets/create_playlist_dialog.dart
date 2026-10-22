import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/piped_service.dart';
import '../screens/Library/library_controller.dart';
import '../screens/Playlist/playlist_screen_controller.dart';
import '/ui/player/play_queue_order.dart';
import '/ui/widgets/snackbar.dart';
import '../../models/playlist.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'riff_sheet.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

class CreateNRenamePlaylistPopup extends StatefulWidget {
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

  @override
  State<CreateNRenamePlaylistPopup> createState() =>
      _CreateNRenamePlaylistPopupState();
}

class _CreateNRenamePlaylistPopupState
    extends State<CreateNRenamePlaylistPopup> {
  final librPlstCntrller = Get.find<LibraryPlaylistsController>();

  bool get isCreateNadd => widget.isCreateNadd;
  bool get renamePlaylist => widget.renamePlaylist;
  List<MediaItem>? get songItems => widget.songItems;
  Playlist? get playlist => widget.playlist;

  /// Editing a library playlist's details (Spotify's Edit details): its
  /// name and its description. A Piped playlist only renames.
  bool get _details =>
      renamePlaylist && playlist != null && !playlist!.isPipedPlaylist;

  late final _description =
      TextEditingController(text: playlist?.ownDescription ?? '');

  @override
  void initState() {
    super.initState();
    // Once, when the dialog opens. In build this ran again on every
    // rebuild (a theme change, e.g. the album-colour theme on each new
    // track) and wiped the name being typed.
    librPlstCntrller.changeCreationMode("local");
    // Renaming starts from the name it has, to change rather than retype.
    librPlstCntrller.textInputController.text = renamePlaylist
        ? (playlist?.title ?? "")
        : defaultNewPlaylistName(songItems: songItems);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// The open playlist page shows the new name and words at once.
  void _showOnItsPage(Playlist renamed) {
    final tag = Key(renamed.playlistId).hashCode.toString();
    if (Get.isRegistered<PlaylistScreenController>(tag: tag)) {
      Get.find<PlaylistScreenController>(tag: tag).playlist.value = renamed;
    }
  }

  Future<void> _submit(
      BuildContext context, LibraryPlaylistsController librPlstCntrller) async {
    if (librPlstCntrller.textInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context, "playlistNameRequired".tr,
          size: SanckBarSize.MEDIUM));
      return;
    }
    if (renamePlaylist) {
      final description = _details ? _description.text.trim() : null;
      final value = await librPlstCntrller.renamePlaylist(playlist!,
          description: description);
      if (!context.mounted) return;
      if (value) {
        _showOnItsPage(playlist!.copyWith(description: description));
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
                    _details
                        ? "editPlaylistDetails".tr
                        : renamePlaylist
                            ? "renamePlaylist".tr
                            : "CreateNewPlaylist".tr,
                    // Two lines: "Create new playlist" reads whole at
                    // large text instead of "Create new pla…".
                    maxLines: 2,
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
            if (_details) ...[
              const SizedBox(height: RiffSpacing.md),
              ModifiedTextField(
                textCapitalization: TextCapitalization.sentences,
                controller: _description,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "playlistDescriptionHint".tr,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: RiffSpacing.lg, vertical: RiffSpacing.md),
                ),
              ),
            ],
            const SizedBox(height: RiffSpacing.lg),
            // Side by side, or stacked under a larger font size.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: RiffSpacing.sm,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("cancel".tr),
                ),
                FilledButton(
                  onPressed: () => _submit(context, librPlstCntrller),
                  child: Text(
                    isCreateNadd
                        ? "createnAdd".tr
                        : _details
                            ? "save".tr
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
