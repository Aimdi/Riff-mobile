import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Search/search_result_screen_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '../screens/Home/home_layout.dart';

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
          // Home shelves pass display titles; search passes type keys
          // ("Community playlists") that need translating, never cutting.
          HomeSectionHeader(
            isHomeContent
                ? content.title
                : '${content.title}'.toLowerCase().removeAllWhitespace.tr,
            top: isHomeContent ? HomeLayout.sectionTop : 20,
            trailing: isHomeContent
                ? null
                : TextButton(
                    onPressed: () => Get.find<SearchResultScreenController>()
                        .viewAllCallback(content.title),
                    style: TextButton.styleFrom(
                      foregroundColor: homeMutedColor(context),
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text("viewAll".tr,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
          ),
          SizedBox(
            // Card height grows with the system text size.
            height: ContentListItem.heightFor(
                    context, ContentListItem.defaultSize) +
                12,
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
