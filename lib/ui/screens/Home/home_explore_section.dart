import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../navigator.dart';
import '../../utils/riff_tokens.dart';
import '../../widgets/collection_play.dart';
import '../../widgets/content_list_widget.dart';
import '../../widgets/snackbar.dart';
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
    final day = DateTime.now()
        .difference(DateTime(DateTime.now().year))
        .inDays;
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
      final accent = theme.colorScheme.secondary;
      final rotating = rotatingShelf(shelves);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
            child: Text(
              'explore'.tr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 19,
                letterSpacing: -0.35,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: shelves.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final title = '${shelves[index].title}';
                return GestureDetector(
                  onLongPress: () => openExploreShelf(title),
                  child: ActionChip(
                    label: Text(title),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.cardColor,
                    surfaceTintColor: Colors.transparent,
                    side: BorderSide(
                      color: accent.withOpacity(0.28),
                      width: RiffTokens.hairline,
                    ),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.titleMedium?.color
                          ?.withOpacity(0.9),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
                    ),
                    onPressed: () =>
                        playOrOpenExploreShelf(shelves[index], title),
                  ),
                );
              },
            ),
          ),
          if (rotating != null) ...[
            const SizedBox(height: 8),
            ContentListWidget(
              content: rotating,
              scrollController: home.scrollControllerFor(
                  'explore_rotating_${rotating.title}'),
            ),
          ],
          const SizedBox(height: 12),
        ],
      );
    });
  }
}

/// Soft vertical gap between Home zones (A / B / C).
/// Kept for callers; prefer plain [SizedBox] for new code.
class HomeZoneDivider extends StatelessWidget {
  const HomeZoneDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 10);
  }
}
