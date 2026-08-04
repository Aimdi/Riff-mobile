import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Search/search_result_screen_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';

class ContentListWidget extends StatelessWidget {
  ///ContentListWidget is used to render a section of Content like a list of Albums or Playlists in HomeScreen
  const ContentListWidget(
      {super.key,
      this.content,
      this.isHomeContent = true,
      this.scrollController});

  ///content will be of class Type AlbumContent or PlaylistContent
  final dynamic content;
  final bool isHomeContent;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final isAlbumContent = content.runtimeType.toString() == "AlbumContent";
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 24, bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    !isHomeContent && content.title.length > 12
                        ? "${content.title.substring(0, 12)}..."
                        : content.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          letterSpacing: -0.35,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                !isHomeContent
                    ? TextButton(
                        onPressed: () {
                          final scrresController =
                              Get.find<SearchResultScreenController>();
                          scrresController.viewAllCallback(content.title);
                        },
                        child: Text("viewAll".tr,
                            style: Theme.of(Get.context!).textTheme.titleSmall))
                    : const SizedBox.shrink()
              ],
            ),
          ),
          SizedBox(
            height: 168,
            child: Scrollbar(
              thickness: GetPlatform.isDesktop ? null : 0,
              controller: scrollController,
              child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  physics: const BouncingScrollPhysics(),
                  separatorBuilder: (context, index) => const SizedBox(
                        width: 12,
                      ),
                  scrollDirection: Axis.horizontal,
                  itemCount: isAlbumContent
                      ? content.albumList.length
                      : content.playlistList.length,
                  itemBuilder: (_, index) {
                    if (isAlbumContent) {
                      final album = content.albumList[index];
                      return ContentListItem(
                        key: ValueKey(album.browseId ?? album.title),
                        content: album,
                      );
                    }
                    final playlist = content.playlistList[index];
                    return ContentListItem(
                      key: ValueKey(playlist.playlistId ?? playlist.title),
                      content: playlist,
                    );
                  }),
            ),
          ),
        ],
      ),
    );
  }
}
