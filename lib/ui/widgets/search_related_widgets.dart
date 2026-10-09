import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Search/search_result_screen_controller.dart';
import '/models/album.dart';
import '/models/artist.dart';
import '/models/playlist.dart';
import '/ui/widgets/content_list_widget.dart';
import 'separate_tab_item_widget.dart';
import '/ui/theme/riff_spacing.dart';

class ResultWidget extends StatelessWidget {
  const ResultWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchResultScreenController searchResScrController =
        Get.find<SearchResultScreenController>();
    return Obx(
      () => Center(
        child: Padding(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
            child: searchResScrController.isResultContentFetced.value
                ? Column(children: [
                    const SizedBox(height: RiffSpacing.xs),
                    ...generateWidgetList(searchResScrController),
                  ])
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  List<Widget> generateWidgetList(
      SearchResultScreenController searchResScrController) {
    List<Widget> list = [];
    // Stable overview order (skip empty stub sections).
    final orderedKeys = [
      ...SearchResultScreenController.preferredRailOrder,
      ...searchResScrController.resultContent.keys.where((k) =>
          k != 'searchEndpoint' &&
          k != 'params' &&
          !SearchResultScreenController.preferredRailOrder.contains(k)),
    ];
    final seen = <String>{};
    for (final key in orderedKeys) {
      if (!seen.add(key)) continue;
      final value = searchResScrController.resultContent[key];
      if (value is! List || value.isEmpty) continue;

      if (key == 'Songs' || key == 'Videos' || key == 'Episodes') {
        list.add(SeparateTabItemWidget(
          items: List<MediaItem>.from(value),
          title: key,
          isCompleteList: false,
          topPadding: list.isEmpty ? RiffSpacing.xs : RiffSpacing.xl,
        ));
      } else if (key == 'Albums') {
        list.add(ContentListWidget(
          content: AlbumContent(title: key, albumList: List<Album>.from(value)),
          isHomeContent: false,
        ));
      } else if (key.contains('playlist') || key == 'Podcasts') {
        list.add(ContentListWidget(
          content: PlaylistContent(
            title: key,
            playlistList: List<Playlist>.from(value),
          ),
          isHomeContent: false,
        ));
      } else if (key.contains('Artist')) {
        list.add(SeparateTabItemWidget(
          items: List<Artist>.from(value),
          title: key,
          isCompleteList: false,
          topPadding: list.isEmpty ? RiffSpacing.xs : RiffSpacing.xl,
        ));
      }
    }

    return list;
  }
}
