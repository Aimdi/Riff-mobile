// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';

import 'additional_operation_dialog.dart';
import 'modified_text_field.dart';
import 'spotify_import_dialog.dart';

enum OperationMode { arrange, delete, addToPlaylist, none }

enum SortType {
  Name,
  Date,
  Duration,
  RecentlyPlayed,
}

Set<SortType> buildSortTypeSet(
    [bool dateRequired = false,
    bool durationRequired = false,
    bool recentlyPlayedRequired = false]) {
  Set<SortType> requiredSortTypes = {};
  if (dateRequired) {
    requiredSortTypes.add(SortType.Date);
  }
  if (durationRequired) {
    requiredSortTypes.add(SortType.Duration);
  }
  if (recentlyPlayedRequired) {
    requiredSortTypes.add(SortType.RecentlyPlayed);
  }
  return requiredSortTypes;
}

class SortWidget extends StatelessWidget {
  /// Additional operations - Delete Multiple songs, Rearrage offline playlist, Add Multiple songs to playlist
  const SortWidget({
    super.key,
    required this.tag,
    this.itemCountTitle = '',
    this.titleLeftPadding = 12,
    this.isAdditionalOperationRequired = true,
    this.requiredSortTypes = const <SortType>{SortType.Name},
    this.isSearchFeatureRequired = false,
    this.isPlaylistRearrageFeatureRequired = false,
    this.isSongDeletetioFeatureRequired = false,
    required this.screenController,
    this.onSearchStart,
    this.onSearch,
    this.onSearchClose,
    this.itemIcon,
    this.startAdditionalOperation,
    this.selectAll,
    this.performAdditionalOperation,
    this.cancelAdditionalOperation,
    this.isImportFeatureRequired = false,
    this.isCloudFeatureRequired = false,
    this.isCloudModeActive,
    this.onCloudToggle,
    required this.onSort,
  });

  /// unique identifier for each sortwidget
  final String tag;
  final String itemCountTitle;
  final IconData? itemIcon;
  final bool isAdditionalOperationRequired;
  final double titleLeftPadding;
  final Set<SortType> requiredSortTypes;
  final bool isSearchFeatureRequired;
  final bool isSongDeletetioFeatureRequired;
  final bool isPlaylistRearrageFeatureRequired;
  final dynamic screenController;
  final Function(SortWidgetController, OperationMode)? startAdditionalOperation;
  final Function(bool)? selectAll;
  final Function()? performAdditionalOperation;
  final Function()? cancelAdditionalOperation;
  final Function(String?)? onSearchStart;
  final Function(String, String?)? onSearch;
  final Function(String?)? onSearchClose;
  final Function(SortType, bool) onSort;
  final bool isImportFeatureRequired;

  /// Shows a cloud icon next to the duration (clock) control.
  final bool isCloudFeatureRequired;

  /// When non-null, drives the selected state of the cloud icon (use with Obx).
  final bool? isCloudModeActive;
  final VoidCallback? onCloudToggle;

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text(
          "importPlaylist".tr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Theme.of(context).textTheme.titleMedium?.color,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "importPlaylistDesc".tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              "importLargeFileNote".tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.file_open),
                label: Text("selectFile".tr),
                onPressed: () {
                  Get.find<LibraryPlaylistsController>()
                      .importPlaylistFromJson(context);
                  // Close only this import dialog (not the Library route).
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor:
                      Theme.of(context).textTheme.titleMedium?.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.library_music),
                label: Text("spotifyImport".tr),
                onPressed: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const SpotifyImportDialog(),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.secondary,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text("close".tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<SortWidgetController>(tag: tag)
        ? Get.find<SortWidgetController>(tag: tag)
        : Get.put(SortWidgetController(), tag: tag);
    final theme = Theme.of(context);
    final muted = theme.textTheme.titleSmall?.color;
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: SizedBox(
        height: 44,
        child: Obx(() {
          if (controller.isSearchingEnabled.value) {
            return _searchField(context, controller);
          }
          return Row(
            children: [
              SizedBox(width: titleLeftPadding),
              Expanded(
                child: Text(
                  _countLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ),
              _sortMenu(context, controller),
              if (isCloudFeatureRequired)
                _iconButton(
                  context,
                  selected: isCloudModeActive == true,
                  icon: isCloudModeActive == true
                      ? Icons.cloud
                      : Icons.cloud_outlined,
                  tooltip: "cloud".tr,
                  onPressed: () => onCloudToggle?.call(),
                ),
              if (isImportFeatureRequired)
                _iconButton(
                  context,
                  icon: Icons.file_download_outlined,
                  tooltip: "importPlaylist".tr,
                  onPressed: () => _showImportDialog(context),
                ),
              if (isSearchFeatureRequired)
                _iconButton(
                  context,
                  icon: Icons.search_rounded,
                  tooltip: "search".tr,
                  onPressed: () {
                    onSearchStart!(tag);
                    controller.toggleSearch();
                  },
                ),
              if (isAdditionalOperationRequired)
                PopupMenuButton<OperationMode>(
                  tooltip: "moreOptions".tr,
                  icon: Icon(Icons.more_vert_rounded, size: 22, color: muted),
                  onSelected: (mode) {
                    showDialog(
                        context: context,
                        builder: (context) => AdditionalOperationDialog(
                              operationMode: mode,
                              screenController: screenController,
                              controller: controller,
                            ));

                    controller.setActiveMode(mode);
                    startAdditionalOperation!(controller, mode);
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<OperationMode>>[
                    if (isPlaylistRearrageFeatureRequired)
                      PopupMenuItem(
                        value: OperationMode.arrange,
                        child: Text("reArrangePlaylist".tr),
                      ),
                    if (isSongDeletetioFeatureRequired)
                      PopupMenuItem(
                        value: OperationMode.delete,
                        child: Text("removeMultiple".tr),
                      ),
                    PopupMenuItem(
                      value: OperationMode.addToPlaylist,
                      child: Text("addMultipleSongs".tr),
                    ),
                  ],
                )
              else
                const SizedBox(width: 6),
            ],
          );
        }),
      ),
    );
  }

  /// Song lists pass a bare number with [itemIcon]: show "14 songs".
  String get _countLabel {
    final n = int.tryParse(itemCountTitle.trim());
    if (itemIcon == null || n == null) return itemCountTitle;
    return n == 1 ? "songCountOne".tr : "songCount".trParams({'count': '$n'});
  }

  static String _sortLabel(SortType type) => switch (type) {
        SortType.Name => "sortName".tr,
        SortType.Date => "sortDate".tr,
        SortType.Duration => "duration".tr,
        SortType.RecentlyPlayed => "recentlyPlayed".tr,
      };

  /// "Name ↑" chip: one menu for the sort key and the direction instead of
  /// a row of unlabeled icons.
  Widget _sortMenu(BuildContext context, SortWidgetController controller) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    final types = <SortType>[
      SortType.Name,
      ...requiredSortTypes.where((t) => t != SortType.Name),
    ];
    return PopupMenuButton<Object>(
      tooltip: "sortBy".tr,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == #direction) {
          controller.onAscendNDescend(onSort);
          return;
        }
        switch (value as SortType) {
          case SortType.Name:
            controller.onSortByName(onSort);
          case SortType.Date:
            controller.onSortByDate(onSort);
          case SortType.Duration:
            controller.onSortByDuration(onSort);
          case SortType.RecentlyPlayed:
            break;
        }
      },
      itemBuilder: (context) => [
        for (final t in types)
          CheckedPopupMenuItem<Object>(
            value: t,
            checked: controller.sortType.value == t,
            child: Text(_sortLabel(t)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: #direction,
          child: Row(
            children: [
              Icon(
                controller.isAscending.value
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 18,
              ),
              const SizedBox(width: 12),
              Text(controller.isAscending.value
                  ? "sortDescending".tr
                  : "sortAscending".tr),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              _sortLabel(controller.sortType.value),
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
            ),
            const SizedBox(width: 2),
            Icon(
              controller.isAscending.value
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 15,
              color: fg?.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(BuildContext context, SortWidgetController controller) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.color?.withOpacity(0.7);
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
      borderSide: BorderSide.none,
    );
    return Padding(
      padding: EdgeInsets.only(left: titleLeftPadding, right: 12),
      child: ModifiedTextField(
        controller: controller.textEditingController,
        textAlignVertical: TextAlignVertical.center,
        autofocus: true,
        onChanged: (value) {
          onSearch!(value, tag);
        },
        cursorColor: theme.colorScheme.secondary,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: theme.colorScheme.onSurface.withOpacity(0.07),
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          hintText: "search".tr,
          hintStyle: TextStyle(color: hint),
          prefixIcon: Icon(Icons.search_rounded, color: hint, size: 20),
          suffixIcon: IconButton(
            splashRadius: 18,
            iconSize: 20,
            tooltip: "close".tr,
            icon: Icon(Icons.close_rounded, color: hint),
            onPressed: () {
              controller.toggleSearch();
              onSearchClose!(tag);
            },
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    bool selected = false,
    VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      icon: Icon(icon),
      color: selected
          ? theme.colorScheme.secondary
          : theme.textTheme.titleSmall?.color,
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class SortWidgetController extends GetxController {
  final Rx<SortType> sortType = SortType.Name.obs;
  final isAscending = true.obs;
  final isSearchingEnabled = false.obs;
  final isRearraningEnabled = false.obs;
  final isDeletionEnabled = false.obs;
  final isAddtoPlaylistEnabled = false.obs;
  final isAllSelected = false.obs;
  TextEditingController textEditingController = TextEditingController();

  void setActiveMode(OperationMode mode) {
    isAddtoPlaylistEnabled.value = OperationMode.addToPlaylist == mode;
    isDeletionEnabled.value = OperationMode.delete == mode;
    isRearraningEnabled.value = OperationMode.arrange == mode;
  }

  void toggleSelectAll(bool val) {
    isAllSelected.value = val;
  }

  void onSortByName(Function onSort) {
    sortType.value = SortType.Name;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDuration(Function onSort) {
    sortType.value = SortType.Duration;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDate(Function onSort) {
    sortType.value = SortType.Date;
    onSort(sortType.value, isAscending.value);
  }

  void onAscendNDescend(Function onSort) {
    isAscending.value = !isAscending.value;
    onSort(sortType.value, isAscending.value);
  }

  void toggleSearch() {
    isSearchingEnabled.value = !isSearchingEnabled.value;
  }
}
