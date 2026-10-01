import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../navigator.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/snackbar.dart';
import 'home_layout.dart';
import 'home_screen_controller.dart';

/// First album/playlist on an Explore shelf — chip tap plays this.
dynamic firstExploreShelfItem(dynamic shelf) {
  try {
    if (shelf.runtimeType.toString() == 'AlbumContent') {
      final list = shelf.albumList as List;
      return list.isEmpty ? null : list.first;
    }
    final list = shelf.playlistList as List;
    return list.isEmpty ? null : list.first;
  } catch (_) {
    return null;
  }
}

void openExploreShelf(String title) {
  Get.toNamed(
    ScreenNavigationSetup.exploreScreen,
    id: ScreenNavigationSetup.id,
    arguments: title,
  );
}

/// Chip tap plays the first album/playlist; long-press opens Explore.
Future<void> playOrOpenExploreShelf(dynamic shelf, String title) async {
  final first = firstExploreShelfItem(shelf);
  if (first != null) {
    final isAlbum = first.runtimeType.toString() == 'Album';
    final id = isAlbum
        ? first.browseId?.toString() ?? ''
        : first.playlistId?.toString() ?? '';
    final name = first.title?.toString() ?? title;
    final ok = await playCollection(
      isAlbum: isAlbum,
      id: id,
      title: name,
    );
    if (ok) return;
    final ctx = Get.context;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(snackbar(
        ctx,
        'operationFailed'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
    return;
  }
  openExploreShelf(title);
}

/// Zone C — editorial buckets collapsed into one chip row (+ optional
/// single rotating carousel). Full carousels live one tap away on Explore.
class HomeExploreSection extends StatelessWidget {
  const HomeExploreSection({super.key});

  static List<dynamic> editorialShelves(HomeScreenController home) => [
        ...home.middleContent,
        ...home.fixedContent,
      ];

  /// One carousel under the chips, rotating by day-of-year.
  static dynamic rotatingShelf(List<dynamic> shelves) {
    if (shelves.isEmpty) return null;
    final day = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return shelves[day % shelves.length];
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return Obx(() {
      final shelves = editorialShelves(home);
      // Touch lengths so Obx tracks updates.
      final _ = home.middleContent.length + home.fixedContent.length;
      if (shelves.isEmpty) return const SizedBox.shrink();

      final theme = Theme.of(context);
      final rotating = rotatingShelf(shelves);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader('explore'.tr),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
              itemCount: shelves.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final title = '${shelves[index].title}';
                return Material(
                  color: homeTileColor(context),
                  shape: StadiumBorder(side: homeTileBorder(context)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => shouldPlayCollectionOnTap()
                        ? playOrOpenExploreShelf(shelves[index], title)
                        : openExploreShelf(title),
                    onLongPress: () => openExploreShelf(title),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        widthFactor: 1,
                        // Explicit size: the theme's labelMedium is a 22sp
                        // title style, which made these chips huge.
                        child: Text(
                          title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.titleMedium?.color,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (rotating != null)
            ContentListWidget(
              content: rotating,
              scrollController: home
                  .scrollControllerFor('explore_rotating_${rotating.title}'),
            ),
        ],
      );
    });
  }
}
