import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'components/search_item.dart';
import '../../utils/riff_tokens.dart';
import '../../utils/theme_controller.dart';
import '../../widgets/modified_text_field.dart';
import '/ui/navigator.dart';
import 'search_screen_controller.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.put(SearchScreenController());
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      // Outer Obx removed: after bottom-nav removal it no longer read any
      // observables (rail was conditional on isBottomNavBarEnabled). Empty
      // Obx throws in GetX and blanks the whole Search screen.
      body: Row(
          children: [
            Container(
              width: 60,
              color: Theme.of(context).navigationRailTheme.backgroundColor,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: topPadding),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new,
                        color: Theme.of(context).textTheme.titleMedium!.color,
                      ),
                      onPressed: () {
                        Get.nestedKey(ScreenNavigationSetup.id)!
                            .currentState!
                            .pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: topPadding, left: 5),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "search".tr,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    ModifiedTextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: searchScreenController.textInputController,
                      textInputAction: TextInputAction.search,
                      onChanged: searchScreenController.onChanged,
                      onSubmitted: (val) {
                        if (val.contains("https://")) {
                          searchScreenController.filterLinks(Uri.parse(val));
                          searchScreenController.reset();
                          return;
                        }
                        Get.toNamed(ScreenNavigationSetup.searchResultScreen,
                            id: ScreenNavigationSetup.id, arguments: val);
                        searchScreenController.addToHistryQueryList(val);
                      },
                      autofocus: true,
                      cursorColor: Theme.of(context).textTheme.bodySmall!.color,
                      decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? RiffSurfaces.elevated
                                  : Theme.of(context).colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          hintText: "searchDes".tr,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(RiffTokens.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: IconButton(
                            onPressed: searchScreenController.reset,
                            icon: const Icon(Icons.close),
                            splashRadius: 16,
                            iconSize: 19,
                          )),
                    ),
                    Expanded(
                      child: Obx(() {
                        final isEmpty = searchScreenController
                                .suggestionList.isEmpty ||
                            searchScreenController.textInputController.text ==
                                "";
                        final list = isEmpty
                            ? searchScreenController.historyQuerylist.toList()
                            : searchScreenController.suggestionList.toList();
                        if (searchScreenController.urlPasted.isTrue) {
                          return ListView(
                            padding:
                                const EdgeInsets.only(top: 5, bottom: 400),
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            children: [
                              InkWell(
                                onTap: () {
                                  searchScreenController.filterLinks(
                                      Uri.parse(searchScreenController
                                          .textInputController.text));
                                  searchScreenController.reset();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10.0),
                                  child: SizedBox(
                                    width: double.maxFinite,
                                    height: 60,
                                    child: Center(
                                        child: Text(
                                      "urlSearchDes".tr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    )),
                                  ),
                                ),
                              )
                            ],
                          );
                        }
                        if (list.isEmpty) {
                          final muted =
                              Theme.of(context).brightness == Brightness.dark
                                  ? RiffSurfaces.textMuted
                                  : Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.color
                                      ?.withOpacity(0.55);
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 24, 24, 80),
                              child: Text(
                                isEmpty
                                    ? 'searchDes'.tr
                                    : 'suggestions'.tr,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: muted,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                            ),
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.only(top: 5, bottom: 400),
                          physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics()),
                          children: [
                            _SearchSectionHeader(
                              title: isEmpty ? 'Recent' : 'suggestions'.tr,
                              trailing: isEmpty
                                  ? TextButton(
                                      onPressed:
                                          searchScreenController.clearHistory,
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'clear'.tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontSize: 12,
                                            ),
                                      ),
                                    )
                                  : null,
                            ),
                            ...list.map((item) => SearchItem(
                                queryString: item,
                                isHistoryString: isEmpty)),
                          ],
                        );
                      }),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? RiffSurfaces.textMuted
        : Theme.of(context).textTheme.titleSmall?.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
