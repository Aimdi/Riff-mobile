import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../navigator.dart';
import '../../widgets/content_list_widget.dart';
import 'home_screen_controller.dart';

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
                return ActionChip(
                  label: Text(title),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: theme.dividerColor.withOpacity(0.35),
                  ),
                  onPressed: () {
                    Get.toNamed(
                      ScreenNavigationSetup.exploreScreen,
                      id: ScreenNavigationSetup.id,
                      arguments: title,
                    );
                  },
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

/// Hairline divider between Home zones (A / B / C).
class HomeZoneDivider extends StatelessWidget {
  const HomeZoneDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withOpacity(0.08),
      ),
    );
  }
}
