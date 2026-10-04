import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'components/search_item.dart';
import '../../widgets/modified_text_field.dart';
import '../../theme/riff_spacing.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import '/ui/navigator.dart';
import 'search_play_top.dart';
import 'search_screen_controller.dart';
import '/ui/widgets/riff_header_bar.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.isRegistered<SearchScreenController>()
        ? Get.find<SearchScreenController>()
        : Get.put(SearchScreenController());
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      // No outer Obx: it would read no observables, and an empty Obx throws
      // in GetX and blanks the whole Search screen.
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          children: [
            RiffHeaderBar(
                hairline: false,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: RiffSpacing.xxs, right: HomeLayout.gutter),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'back'.tr,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: () {
                          Get.nestedKey(ScreenNavigationSetup.id)!
                              .currentState!
                              .pop();
                        },
                      ),
                      Expanded(
                        child: _SearchField(controller: searchScreenController),
                      ),
                    ],
                  ),
                )),
            Expanded(
              child: RiffScrollUnder(child: Obx(() {
                final isEmpty = searchScreenController.suggestionList.isEmpty ||
                    searchScreenController.textInputController.text == "";
                final list = isEmpty
                    ? searchScreenController.historyQuerylist.toList()
                    : searchScreenController.suggestionList.toList();
                if (searchScreenController.urlPasted.isTrue) {
                  return ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 400),
                    children: [
                      SearchRow(
                        icon: Icons.link_rounded,
                        label: "urlSearchDes".tr,
                        onTap: () {
                          searchScreenController.filterLinks(Uri.parse(
                              searchScreenController.textInputController.text));
                          searchScreenController.reset();
                        },
                      ),
                    ],
                  );
                }
                if (list.isEmpty) {
                  return PodcastEmptyState(
                    icon: Icons.search_rounded,
                    message: 'searchDes'.tr,
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: 400),
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    HomeSectionHeader(
                      isEmpty ? 'recentSearches'.tr : 'suggestions'.tr,
                      top: 16,
                      trailing: isEmpty
                          ? TextButton(
                              onPressed: searchScreenController.clearHistory,
                              style: TextButton.styleFrom(
                                foregroundColor: homeMutedColor(context),
                                minimumSize: const Size(0, 30),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: Text('clear'.tr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                          color: homeMutedColor(context))),
                            )
                          : null,
                    ),
                    ...list.map((item) => SearchItem(
                          queryString: item,
                          isHistoryString: isEmpty,
                          typed: isEmpty
                              ? ''
                              : searchScreenController.textInputController.text,
                        )),
                    Padding(
                      padding: const EdgeInsets.only(
                          left: HomeLayout.gutter,
                          top: RiffSpacing.lg,
                          right: HomeLayout.gutter),
                      child: Text('searchOpenResultsHint'.tr,
                          style: homeCardSubtitleStyle(context)),
                    ),
                  ],
                );
              })),
            )
          ],
        ),
      ),
    );
  }
}

/// Pill search field; the clear button shows only while there is text.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final SearchScreenController controller;

  void _submit(BuildContext context, String val) {
    submitSearchQuery(
      val,
      onLink: (uri) {
        controller.filterLinks(uri);
        controller.reset();
      },
      onRemember: controller.addToHistryQueryList,
      onOpenResults: (q) {
        Get.toNamed(ScreenNavigationSetup.searchResultScreen,
            id: ScreenNavigationSetup.id, arguments: q);
      },
      onPlayFailed: () => showSearchPlayFailed(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ModifiedTextField(
        textCapitalization: TextCapitalization.sentences,
        controller: controller.textInputController,
        textInputAction: TextInputAction.search,
        onChanged: controller.onChanged,
        onSubmitted: (val) => _submit(context, val),
        autofocus: true,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        textAlignVertical: TextAlignVertical.center,
        cursorColor: Theme.of(context).colorScheme.secondary,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: homeTileColor(context),
          contentPadding: EdgeInsets.zero,
          hintText: "searchDes".tr,
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller.textInputController,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'clear'.tr,
                    onPressed: controller.reset,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
          ),
        ),
      ),
    );
  }
}
