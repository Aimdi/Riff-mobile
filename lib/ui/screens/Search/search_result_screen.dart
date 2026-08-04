import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/screens/Plugins/seeker_screen.dart';
import '/ui/screens/Search/search_result_screen_v2.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../navigator.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/loader.dart';
import '../../widgets/search_related_widgets.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreen extends StatelessWidget {
  const SearchResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchResScrController = Get.put(SearchResultScreenController());
    return GetPlatform.isDesktop
        ? const SearchResultScreenBN()
        : Scaffold(
            body: Row(
              children: [
                // Slim left rail: put rotated labels in the icon slot so
                // NavigationRail doesn't expand to unrotated text width.
                SizedBox(
                  width: 48,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 200),
                      child: Obx(
                        () => NavigationRail(
                          onDestinationSelected:
                              searchResScrController.onDestinationSelected,
                          minWidth: 48,
                          groupAlignment: -1,
                          labelType: NavigationRailLabelType.none,
                          destinations: (searchResScrController
                                      .isResultContentFetced.value &&
                                  searchResScrController.railItems.isNotEmpty)
                              ? [
                                  railDestination("results".tr),
                                  ...(searchResScrController.railItems.map(
                                      (element) => railDestination(element))),
                                ]
                              : [
                                  railDestination("results".tr),
                                  railDestination("")
                                ],
                          leading: Column(
                            children: [
                              SizedBox(
                                height: context.isLandscape ? 50 : 80,
                              ),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 40, minHeight: 40),
                                icon: Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 20,
                                  color: Theme.of(context)
                                      .textTheme
                                      .titleMedium!
                                      .color,
                                ),
                                onPressed: () {
                                  Get.nestedKey(ScreenNavigationSetup.id)!
                                      .currentState!
                                      .pop();
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                          selectedIndex: searchResScrController
                              .navigationRailCurrentIndex.value,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GetX<SearchResultScreenController>(
                    builder: (controller) => AnimatedScreenTransition(
                      enabled: Get.find<SettingsScreenController>()
                          .isTransitionAnimationDisabled
                          .isFalse,
                      resverse: controller.isTabTransitionReversed,
                      child: Center(
                        key: ValueKey<int>(
                            controller.navigationRailCurrentIndex.toInt() * 8),
                        child: Body(
                            searchResScrController: searchResScrController),
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
  }

  NavigationRailDestination railDestination(String label) {
    final text = label.toLowerCase().removeAllWhitespace.tr;
    return NavigationRailDestination(
      icon: _RailLabel(text),
      selectedIcon: _RailLabel(text, selected: true),
      label: const SizedBox.shrink(),
    );
  }
}

class _RailLabel extends StatelessWidget {
  const _RailLabel(this.label, {this.selected = false});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = selected
        ? theme.navigationRailTheme.selectedLabelTextStyle
        : theme.navigationRailTheme.unselectedLabelTextStyle;
    return SizedBox(
      width: 28,
      height: 72,
      child: Center(
        child: RotatedBox(
          quarterTurns: -1,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (style ?? theme.textTheme.labelSmall)?.copyWith(fontSize: 12),
          ),
        ),
      ),
    );
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
          return const Center(child: LoadingIndicator());
        }
        // Soulseek-only rail still means YTM returned nothing — show empty
        // state on Results rather than a blank column.
        final ytmRails = searchResScrController.railItems
            .where((r) => !searchResScrController.isSoulseekRail(r))
            .toList();
        if (ytmRails.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "nomatch".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text("'${searchResScrController.queryString.value}'"),
                if (searchResScrController.railItems
                    .any(searchResScrController.isSoulseekRail)) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      final idx = searchResScrController.railItems.indexWhere(
                          searchResScrController.isSoulseekRail);
                      if (idx >= 0) {
                        searchResScrController.onDestinationSelected(idx + 1);
                      }
                    },
                    icon: const Icon(Icons.search),
                    label: Text('soulseek'.tr),
                  ),
                ],
              ],
            ),
          );
        }
        return const ResultWidget();
      });
    } else {
      if (searchResScrController.isResultContentFetced.isTrue) {
        final topPadding = context.isLandscape ? 50.0 : 80.0;
        final name = searchResScrController.railItems[
            searchResScrController.navigationRailCurrentIndex.value - 1];
        if (searchResScrController.isSoulseekRail(name)) {
          return Padding(
            padding: EdgeInsets.only(top: topPadding),
            child: SeekerScreen(
              embedded: true,
              initialQuery: searchResScrController.queryString.value,
            ),
          );
        }
        return SeparateTabItemWidget(
          items: const [],
          title: name,
          topPadding: topPadding,
          scrollController: searchResScrController.scrollControllers[name],
        );
      }
    }
    return const SizedBox.shrink();
  }
}
