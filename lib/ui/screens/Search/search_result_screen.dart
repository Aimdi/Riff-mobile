import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Plugins/seeker_screen.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../navigator.dart';
import '../../theme/riff_spacing.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/search_related_widgets.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreen extends StatelessWidget {
  const SearchResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchResScrController =
        Get.isRegistered<SearchResultScreenController>()
            ? Get.find<SearchResultScreenController>()
            : Get.put(SearchResultScreenController());
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QueryBar(controller: searchResScrController),
            const SizedBox(height: 8),
            _FilterChips(controller: searchResScrController),
            const SizedBox(height: 4),
            Expanded(
              child: GetX<SearchResultScreenController>(
                builder: (controller) => AnimatedScreenTransition(
                  enabled: Get.find<SettingsScreenController>()
                      .isTransitionAnimationDisabled
                      .isFalse,
                  resverse: controller.isTabTransitionReversed,
                  child: KeyedSubtree(
                    key: ValueKey<int>(
                        controller.navigationRailCurrentIndex.toInt() * 8),
                    child: Body(searchResScrController: searchResScrController),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back button and the query in a pill; tapping the pill goes back to the
/// search field to change it.
class _QueryBar extends StatelessWidget {
  const _QueryBar({required this.controller});
  final SearchResultScreenController controller;

  void _back() => Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.xxs, right: HomeLayout.gutter),
      child: Row(
        children: [
          IconButton(
            tooltip: 'back'.tr,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _back,
          ),
          Expanded(
            child: Material(
              color: homeTileColor(context),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _back,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.search_rounded, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Obx(() => Text(
                              controller.queryString.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                            )),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "All" plus one chip per result type (and Soulseek when installed).
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.controller});
  final SearchResultScreenController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final labels = [
        'allResults'.tr,
        if (controller.isResultContentFetced.value)
          ...controller.railItems
              .map((e) => e.toLowerCase().removeAllWhitespace.tr),
      ];
      final selected = controller.navigationRailCurrentIndex.value;
      final accent = Theme.of(context).colorScheme.secondary;
      return SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final active = i == selected;
            return Material(
              color: active ? accent : homeTileColor(context),
              shape: StadiumBorder(
                  side: active ? BorderSide.none : homeTileBorder(context)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => controller.onDestinationSelected(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: active
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    });
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
    required this.searchResScrController,
  });

  final SearchResultScreenController searchResScrController;

  @override
  Widget build(BuildContext context) {
    if (searchResScrController.navigationRailCurrentIndex.value == 0) {
      return Obx(() {
        if (searchResScrController.isResultContentFetced.isFalse) {
          return const SongListShimmer(itemCount: 8, topPadding: 12);
        }
        // Soulseek-only rail still means YTM returned nothing — show empty
        // state on Results rather than a blank column.
        final ytmRails = searchResScrController.railItems
            .where((r) => !searchResScrController.isSoulseekRail(r))
            .toList();
        if (ytmRails.isEmpty) {
          final hasSoulseek = searchResScrController.railItems
              .any(searchResScrController.isSoulseekRail);
          return PodcastEmptyState(
            icon: Icons.search_off_rounded,
            message:
                "${"nomatch".tr}\n'${searchResScrController.queryString.value}'",
            actionLabel: hasSoulseek ? 'soulseek'.tr : null,
            actionIcon: Icons.search_rounded,
            onAction: hasSoulseek
                ? () {
                    final idx = searchResScrController.railItems
                        .indexWhere(searchResScrController.isSoulseekRail);
                    if (idx >= 0) {
                      searchResScrController.onDestinationSelected(idx + 1);
                    }
                  }
                : null,
          );
        }
        return const ResultWidget();
      });
    } else {
      if (searchResScrController.isResultContentFetced.isTrue) {
        final name = searchResScrController.railItems[
            searchResScrController.navigationRailCurrentIndex.value - 1];
        if (searchResScrController.isSoulseekRail(name)) {
          return SeekerScreen(
            embedded: true,
            initialQuery: searchResScrController.queryString.value,
          );
        }
        return SeparateTabItemWidget(
          items: const [],
          title: name,
          topPadding: 8,
          scrollController: searchResScrController.scrollControllers[name],
        );
      }
    }
    return const SizedBox.shrink();
  }
}
