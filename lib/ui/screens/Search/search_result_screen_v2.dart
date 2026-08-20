import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/search_related_widgets.dart';
import 'package:harmonymusic/ui/widgets/shimmer_widgets/song_list_shimmer.dart';

import '../../navigator.dart';
import '../../widgets/separate_tab_item_widget.dart';
import '../Plugins/seeker_screen.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreenBN extends StatelessWidget {
  const SearchResultScreenBN({super.key});

  @override
  Widget build(BuildContext context) {
    final SearchResultScreenController searchResScrController =
        Get.find<SearchResultScreenController>();
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      body: Padding(
          padding: EdgeInsets.only(
            top: topPadding,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 55,
                    child: Center(
                      child: IconButton(
                        onPressed: () {
                          Get.nestedKey(ScreenNavigationSetup.id)!
                              .currentState!
                              .pop();
                        },
                        icon: const Icon(Icons.arrow_back_ios_new),
                      ),
                    ),
                  ),
                  Expanded(
                      child: Column(children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "searchRes".tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Obx(
                        () => Text(
                          "${"for1".tr} \"${searchResScrController.queryString.value}\"",
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ]))
                ],
              ),
              Expanded(
                child: Obx(
                  () {
                    if (searchResScrController.isResultContentFetced.isFalse) {
                      return const SongListShimmer(itemCount: 8, topPadding: 12);
                    }
                    final ytmRails = searchResScrController.railItems
                        .where((r) =>
                            !searchResScrController.isSoulseekRail(r))
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
                            Text(
                                "'${searchResScrController.queryString.value}'"),
                            if (searchResScrController.railItems.any(
                                searchResScrController.isSoulseekRail)) ...[
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: () {
                                  final idx = searchResScrController.railItems
                                      .indexWhere(searchResScrController
                                          .isSoulseekRail);
                                  if (idx >= 0) {
                                    searchResScrController
                                        .onDestinationSelected(idx + 1);
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
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(left: 15.0, top: 10),
                            child: ButtonsTabBar(
                              onTap:
                                  searchResScrController.onDestinationSelected,

                              controller: searchResScrController.tabController,
                              contentPadding:
                                  const EdgeInsets.only(left: 15, right: 15),
                              backgroundColor: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.color!,
                              unselectedBackgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              borderWidth: 0,
                              buttonMargin: const EdgeInsets.only(
                                  right: 10, left: 4, top: 4, bottom: 4),
                              borderColor: Colors.black,
                              labelStyle: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                              unselectedLabelStyle: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.color!,
                                fontWeight: FontWeight.bold,
                              ),
                              // Add your tabs here
                              tabs: [
                                Tab(text: "results".tr),
                                ...searchResScrController.railItems
                                    .map((item) => Tab(
                                          text: item
                                              .toLowerCase()
                                              .removeAllWhitespace
                                              .tr,
                                        ))
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 15.0),
                              child: TabBarView(
                                controller:
                                    searchResScrController.tabController,
                                children: [
                                  const ResultWidget(
                                    isv2Used: true,
                                  ),
                                  ...searchResScrController.railItems
                                      .map((tabName) {
                                    if (searchResScrController
                                        .isSoulseekRail(tabName)) {
                                      return SeekerScreen(
                                        embedded: true,
                                        initialQuery: searchResScrController
                                            .queryString.value,
                                      );
                                    }
                                    if (tabName == "Songs" ||
                                        tabName == "Videos") {
                                      return SeparateTabItemWidget(
                                        isResultWidget: true,
                                        hideTitle: true,
                                        items: const [],
                                        title: tabName,
                                        isCompleteList: true,
                                        scrollController: searchResScrController
                                            .scrollControllers[tabName],
                                      );
                                    } else {
                                      return SeparateTabItemWidget(
                                        title: tabName,
                                        hideTitle: true,
                                        items: const [],
                                        scrollController: searchResScrController
                                            .scrollControllers[tabName],
                                      );
                                    }
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                  },
                ),
              )
            ],
          )),
    );
  }
}
