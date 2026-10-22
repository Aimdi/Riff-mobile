import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/widgets/sort_widget.dart' show OperationMode;
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'image_widget.dart';
import 'riff_marquee.dart';

/// A row's key in the rearrange list: its song's, so a dragged row's cover
/// and title move with it (index keys left each row where it was and gave
/// it the next song, redrawing them all). A song that's in the list more
/// than once gets one key per copy.
Key rearrangeRowKey(List<dynamic> items, int index) {
  final id = (items[index] as MediaItem).id;
  var copy = 0;
  for (var i = 0; i < index; i++) {
    if ((items[i] as MediaItem).id == id) copy++;
  }
  return ValueKey('$id#$copy');
}

class ModificationList extends StatelessWidget {
  const ModificationList(
      {super.key, required this.mode, this.screenController});
  final OperationMode mode;
  final dynamic screenController;

  @override
  Widget build(BuildContext context) {
    final items = screenController.additionalOperationTempList;
    if (mode == OperationMode.arrange) {
      return Expanded(
        child: ReorderableListView.builder(
            padding: const EdgeInsets.only(
                right: RiffSpacing.xs, bottom: RiffSpacing.listEnd),
            itemBuilder: (context, index) => ListTile(
                  key: rearrangeRowKey(items, index),
                  onTap: () {},
                  // Room on the right for the reorder handle.
                  contentPadding: const EdgeInsets.only(
                      left: RiffSpacing.xs, right: RiffComponentSizes.iconHit),
                  leading: ImageWidget(
                    size: RiffComponentSizes.rowArt,
                    song: items[index],
                  ),
                  title: RiffMarquee(
                    delay: const Duration(milliseconds: 300),
                    duration: const Duration(seconds: 5),
                    id: items[index].title.hashCode.toString(),
                    child: Text(
                      items[index].title.length > 50
                          ? items[index].title.substring(0, 50)
                          : items[index].title,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  subtitle: Text(
                    "${items[index].artist}",
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            itemCount: items.length,
            onReorder: (old_, new_) {
              if (old_ < new_) {
                new_--;
              }
              final list = items.toList();
              final item = list.removeAt(
                old_,
              );
              list.insert(new_, item);
              screenController.additionalOperationTempList.value = list;
            }),
      );
    } else if (mode == OperationMode.addToPlaylist ||
        mode == OperationMode.delete) {
      return Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(
              right: RiffSpacing.xs, bottom: RiffSpacing.listEnd),
          itemCount: items.length,
          itemBuilder: (context, index) => ListTile(
            onTap: () {
              screenController.additionalOperationTempMap[index] =
                  !screenController.additionalOperationTempMap[index]!;
              screenController.checkIfAllSelected();
            },
            contentPadding: const EdgeInsets.only(
                left: RiffSpacing.xs, right: RiffSpacing.x3l),
            leading: SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Obx(
                    () => Checkbox(
                      tristate: true,
                      value: screenController.additionalOperationTempMap[index],
                      onChanged: (val) {
                        screenController.additionalOperationTempMap[index] =
                            val!;
                        screenController.checkIfAllSelected();
                      },
                      visualDensity:
                          const VisualDensity(horizontal: -3, vertical: -3),
                      shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.all(Radius.circular(RiffRadii.xs))),
                    ),
                  ),
                  ImageWidget(
                    size: RiffComponentSizes.rowArt,
                    song: items[index],
                  ),
                ],
              ),
            ),
            title: RiffMarquee(
              delay: const Duration(milliseconds: 300),
              duration: const Duration(seconds: 5),
              id: items[index].title.hashCode.toString(),
              child: Text(
                items[index].title.length > 50
                    ? items[index].title.substring(0, 50)
                    : items[index].title,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            subtitle: Text(
              "${items[index].artist}",
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
