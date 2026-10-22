import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'components/search_item.dart';
import 'components/search_recent_row.dart';
import 'components/search_pill.dart';
import 'components/voice_search_button.dart';
import '../../widgets/modified_text_field.dart';
import '../../theme/riff_spacing.dart';
import '../../theme/riff_tokens.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import '/services/search_recents.dart';
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
    final topPadding = riffTabTop(context);
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
                final queries = searchScreenController.suggestionList.toList();
                final items = searchScreenController.suggestedItems.toList();
                final isEmpty = (queries.isEmpty && items.isEmpty) ||
                    searchScreenController.textInputController.text == "";
                final list = isEmpty
                    ? searchScreenController.historyQuerylist.toList()
                    : queries;
                // What YouTube Music would open for it, after the searches.
                final suggested = isEmpty
                    ? const <SearchRecent>[]
                    : items.map(SearchRecent.of).whereType<SearchRecent>();
                // What was opened from search, before the words searched.
                SearchRecents.rev.value;
                final recents =
                    isEmpty ? SearchRecents.items : const <SearchRecent>[];
                if (searchScreenController.urlPasted.isTrue) {
                  return ListView(
                    padding:
                        const EdgeInsets.only(top: RiffSpacing.md, bottom: 400),
                    children: [
                      SearchRow(
                        icon: Icons.link_rounded,
                        label: "urlSearchDes".tr,
                        onTap: () {
                          searchScreenController.openLinkIn(
                              searchScreenController.textInputController.text);
                          searchScreenController.reset();
                        },
                      ),
                    ],
                  );
                }
                if (list.isEmpty && recents.isEmpty && suggested.isEmpty) {
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
                      top: RiffSpacing.lg,
                      trailing: isEmpty
                          ? TextButton(
                              onPressed: () {
                                searchScreenController.clearHistory();
                                SearchRecents.clear();
                              },
                              // §5.5 text button: accent, theme type. The
                              // 30 dp header row still sets the height.
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: RiffSpacing.md),
                              ),
                              child: Text('clear'.tr),
                            )
                          : null,
                    ),
                    ...recents.map((recent) => SearchRecentRow(
                        key: ValueKey('${recent.kind.name}:${recent.id}'),
                        recent: recent)),
                    ...list.map((item) => SearchItem(
                          queryString: item,
                          isHistoryString: isEmpty,
                          typed: isEmpty
                              ? ''
                              : searchScreenController.textInputController.text,
                        )),
                    ...suggested.map((item) => SearchRecentRow(
                        key: ValueKey('suggested:${item.kind.name}:${item.id}'),
                        recent: item,
                        removable: false)),
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

/// Pill search field; the clear button shows only while there is text,
/// the mic (voice search) while there's none.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final SearchScreenController controller;

  void _submit(BuildContext context, String val) {
    submitSearchQuery(
      val,
      onLink: (text) {
        controller.openLinkIn(text);
        controller.reset();
      },
      onRemember: controller.addToHistryQueryList,
      onOpenResults: (q) {
        Get.toNamed(ScreenNavigationSetup.searchResultScreen,
            id: ScreenNavigationSetup.id, arguments: q);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: RiffComponentSizes.searchField,
      child: ModifiedTextField(
        textCapitalization: TextCapitalization.sentences,
        controller: controller.textInputController,
        textInputAction: TextInputAction.search,
        onChanged: controller.onChanged,
        onSubmitted: (val) => _submit(context, val),
        autofocus: true,
        style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        textAlignVertical: TextAlignVertical.center,
        cursorColor: scheme.primary,
        // §5.8: surface1 pill, no border at rest, 1 px accent ring on focus.
        decoration: searchFieldDecoration(
          context,
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller.textInputController,
            builder: (context, value, _) => value.text.isEmpty
                // What the mic heard is searched as Enter would.
                ? VoiceSearchButton(onHeard: (q) => _submit(context, q))
                : IconButton(
                    tooltip: 'clear'.tr,
                    onPressed: controller.reset,
                    color: scheme.onSurfaceVariant,
                    style: IconButton.styleFrom(
                      minimumSize:
                          const Size.square(RiffComponentSizes.iconHit),
                    ),
                    icon: const Icon(Icons.close_rounded,
                        size: RiffComponentSizes.trailingIcon),
                  ),
          ),
        ),
      ),
    );
  }
}
