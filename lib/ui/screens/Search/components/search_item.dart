import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/screens/Search/search_screen_controller.dart';

import '../../../navigator.dart';

class SearchItem extends StatelessWidget {
  final String queryString;
  final bool isHistoryString;
  const SearchItem(
      {super.key, required this.queryString, required this.isHistoryString});

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.find<SearchScreenController>();
    final iconColor = Theme.of(context).textTheme.titleMedium!.color;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 10, right: 4),
      onTap: () {
        Get.toNamed(ScreenNavigationSetup.searchResultScreen,
            id: ScreenNavigationSetup.id, arguments: queryString);
        searchScreenController.addToHistryQueryList(queryString);
        // for Desktop searchbar
        if (GetPlatform.isDesktop) {
          searchScreenController.focusNode.unfocus();
        }
      },
      leading: Icon(
        isHistoryString ? Icons.history : Icons.search,
        size: 20,
        color: iconColor,
      ),
      minLeadingWidth: 20,
      horizontalTitleGap: 10,
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      title: Text(queryString),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHistoryString)
            IconButton(
              iconSize: 16,
              splashRadius: 14,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
              onPressed: () {
                searchScreenController.removeQueryFromHistory(queryString);
              },
              icon: Icon(Icons.clear, color: iconColor),
            ),
          IconButton(
            iconSize: 16,
            splashRadius: 14,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -2),
            onPressed: () {
              searchScreenController.suggestionInput(queryString);
            },
            icon: Icon(Icons.north_west, color: iconColor),
          ),
        ],
      ),
    );
  }
}
