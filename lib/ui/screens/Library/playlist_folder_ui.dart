import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/playlist_folders.dart';
import '/services/library_view_mode.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/utils/riff_tokens.dart' show RiffTokens;
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;
import '../../navigator.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import 'library.dart' show libraryGridMetrics;
import 'library_controller.dart';

/// "1 playlist" / "12 playlists".
String folderPlaylistCount(int n) => n == 1
    ? 'folderPlaylistsOne'.tr
    : 'folderPlaylists'.trParams({'count': '$n'});

/// The Library's playlists now, for a folder's.
List<Playlist> _libraryPlaylists() {
  if (!Get.isRegistered<LibraryPlaylistsController>()) return const [];
  final library = Get.find<LibraryPlaylistsController>();
  // While the Library is searched, all of them are kept aside.
  return library.tempListContainer.isNotEmpty
      ? library.tempListContainer
      : library.libraryPlaylists;
}

/// A folder in Library › Playlists, laid out as a playlist's card (or row,
/// [asRow]): a folder glyph for its cover, its name and how many
/// playlists it holds. A tap opens it, a long-press offers Rename and
/// Delete.
class PlaylistFolderTile extends StatelessWidget {
  const PlaylistFolderTile({
    super.key,
    required this.folder,
    required this.count,
    required this.size,
    this.asRow = false,
  });

  final PlaylistFolder folder;

  /// Its playlists in the Library.
  final int count;
  final double size;
  final bool asRow;

  Widget _cover(BuildContext context) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
            color: Theme.of(context).primaryColorLight,
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm)),
        child: Center(
          child: Icon(
            Icons.folder_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            size: size * 0.32,
          ),
        ),
      );

  void _open() => Get.to(() => PlaylistFolderScreen(folderId: folder.id),
      id: ScreenNavigationSetup.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = Text(folderPlaylistCount(count),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: muted));
    if (asRow) {
      return Stack(
        children: [
          InkWell(
            onTap: _open,
            onLongPress: () => showFolderActions(context, folder),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: HomeLayout.gutter, vertical: RiffSpacing.sm),
              child: Row(
                children: [
                  SizedBox.square(dimension: size, child: _cover(context)),
                  const SizedBox(width: RiffSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: RiffSpacing.xxs),
                        subtitle,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const RiffRowHairline(),
        ],
      );
    }
    return InkWell(
      onTap: _open,
      onLongPress: () => showFolderActions(context, folder),
      child: SizedBox(
        width: size,
        height: ContentListItem.heightFor(context, size),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(context),
            const SizedBox(height: RiffSpacing.sm),
            Text(folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium),
            const SizedBox(height: RiffSpacing.xxs),
            subtitle,
          ],
        ),
      ),
    );
  }
}

/// A folder's page: its playlists, as the Library shows them (grid or
/// list); ⋮ renames or deletes it.
class PlaylistFolderScreen extends StatelessWidget {
  const PlaylistFolderScreen({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        PlaylistFolders.rev.value;
        final folder = PlaylistFolders.byId(folderId);
        if (folder == null) return const SizedBox.shrink();
        final playlists = folderPlaylists(folder, _libraryPlaylists());
        return Column(
          children: [
            RiffPageHeader(
              folder.name,
              subtitle: folderPlaylistCount(playlists.length),
              actions: [
                IconButton(
                  tooltip: 'moreOptions'.tr,
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () =>
                      showFolderActions(context, folder, onItsPage: true),
                ),
              ],
            ),
            Expanded(
              child: playlists.isEmpty
                  ? PodcastEmptyState(
                      icon: Icons.folder_open_rounded,
                      message: 'folderEmptyDes'.tr,
                    )
                  : LibraryViewMode.list.isTrue
                      ? ListView.builder(
                          padding: const EdgeInsets.only(
                              top: RiffSpacing.xs, bottom: RiffSpacing.listEnd),
                          itemCount: playlists.length,
                          itemBuilder: (context, i) => ContentListItem(
                            content: playlists[i],
                            isLibraryItem: true,
                            size: RiffComponentSizes.rowArt,
                            asRow: true,
                          ),
                        )
                      : LayoutBuilder(builder: (context, constraints) {
                          final grid = libraryGridMetrics(constraints.maxWidth);
                          return GridView.builder(
                            padding: const EdgeInsets.only(
                                left: HomeLayout.gutter,
                                top: RiffSpacing.sm,
                                right: HomeLayout.gutter,
                                bottom: RiffSpacing.listEnd),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: grid.columns,
                              crossAxisSpacing: HomeLayout.cardGap,
                              mainAxisSpacing: RiffSpacing.md,
                              mainAxisExtent: ContentListItem.heightFor(
                                  context, grid.cover),
                            ),
                            itemCount: playlists.length,
                            itemBuilder: (context, i) => ContentListItem(
                              content: playlists[i],
                              isLibraryItem: true,
                              size: grid.cover,
                            ),
                          );
                        }),
            ),
          ],
        );
      }),
    );
  }
}

/// A folder's name, asked for: [initial] to start from (renaming). Null
/// when cancelled or left empty.
Future<String?> askFolderName(BuildContext context,
    {required String title, String initial = ''}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'folderName'.tr, isDense: true),
        onSubmitted: (name) => Navigator.of(ctx).pop(name.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr)),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(field.text.trim()),
          child: Text(initial.isEmpty ? 'create'.tr : 'rename'.tr),
        ),
      ],
    ),
  ).then((name) => name == null || name.isEmpty ? null : name);
}

/// [playlist]'s ⋮ › Move to folder: into one of the folders or a new one,
/// or out of its folder.
void showMoveToFolderSheet(BuildContext context, Playlist playlist) {
  final target = undoSnackbarTarget(context);
  final current = PlaylistFolders.folderOf(playlist.playlistId);
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
      child: ListTileTheme.merge(
        titleTextStyle: Theme.of(sheet).textTheme.bodyLarge,
        iconColor: Theme.of(sheet).colorScheme.onSurface,
        child: IconTheme.merge(
          data: const IconThemeData(size: RiffComponentSizes.headerIcon),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: Text('newFolder'.tr),
                  onTap: () async {
                    Navigator.of(sheet).pop();
                    final name =
                        await askFolderName(context, title: 'newFolder'.tr);
                    if (name == null) return;
                    final folder = await PlaylistFolders.create(name,
                        playlistId: playlist.playlistId);
                    showUndoSnackbar(target,
                        'movedToFolder'.trParams({'name': folder.name}));
                  },
                ),
                for (final folder in PlaylistFolders.folders)
                  ListTile(
                    leading: Icon(folder.id == current?.id
                        ? Icons.folder_rounded
                        : Icons.folder_outlined),
                    title: Text(folder.name),
                    trailing: folder.id == current?.id
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(sheet).colorScheme.primary)
                        : null,
                    onTap: () async {
                      Navigator.of(sheet).pop();
                      if (folder.id == current?.id) return;
                      HapticFeedback.lightImpact();
                      await PlaylistFolders.move(
                          playlist.playlistId, folder.id);
                      showUndoSnackbar(target,
                          'movedToFolder'.trParams({'name': folder.name}));
                    },
                  ),
                if (current != null)
                  ListTile(
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    title: Text('removeFromFolder'.tr),
                    onTap: () async {
                      Navigator.of(sheet).pop();
                      await PlaylistFolders.move(playlist.playlistId, null);
                      showUndoSnackbar(target, 'removedFromFolder'.tr);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A folder's long-press, or its page's ⋮ ([onItsPage]): Rename,
/// Delete (its playlists go back among the rest; Undo puts it back).
void showFolderActions(BuildContext context, PlaylistFolder folder,
    {bool onItsPage = false}) {
  HapticFeedback.mediumImpact();
  final target = undoSnackbarTarget(context);
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      // Sheet rows per RIFF_UI_RESTYLE.md §5.10.
      child: ListTileTheme.merge(
        titleTextStyle: Theme.of(sheet).textTheme.bodyLarge,
        iconColor: Theme.of(sheet).colorScheme.onSurface,
        child: IconTheme.merge(
          data: const IconThemeData(size: RiffComponentSizes.headerIcon),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('renameFolder'.tr),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  final name = await askFolderName(context,
                      title: 'renameFolder'.tr, initial: folder.name);
                  if (name != null) {
                    await PlaylistFolders.rename(folder.id, name);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_delete_outlined),
                title: Text('deleteFolder'.tr),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  final deleted = await PlaylistFolders.delete(folder.id);
                  if (deleted == null) return;
                  // Its page goes with it.
                  if (onItsPage && context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                  showUndoSnackbar(target, 'folderDeleted'.tr,
                      onUndo: () =>
                          PlaylistFolders.restore(deleted.$1, deleted.$2));
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
