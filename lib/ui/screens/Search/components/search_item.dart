import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/screens/Search/search_play_top.dart';
import '/ui/screens/Search/search_screen_controller.dart';

import '/ui/theme/riff_spacing.dart';
import '../../../navigator.dart';
import '../../Home/home_layout.dart';

/// A recent search or a suggestion. Tap plays the top song (same as Enter),
/// long-press opens the full results; the trailing button removes a recent
/// search or copies a suggestion into the field.
class SearchItem extends StatelessWidget {
  final String queryString;
  final bool isHistoryString;

  /// What is in the field, so a suggestion can bold the part it adds.
  final String typed;
  const SearchItem(
      {super.key,
      required this.queryString,
      required this.isHistoryString,
      this.typed = ''});

  void _openResults(SearchScreenController c, String q) {
    Get.toNamed(ScreenNavigationSetup.searchResultScreen,
        id: ScreenNavigationSetup.id, arguments: q);
    c.addToHistryQueryList(q);
    if (GetPlatform.isDesktop) c.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final searchScreenController = Get.find<SearchScreenController>();
    final muted = homeMutedColor(context);
    return SearchRow(
      icon: isHistoryString ? Icons.history_rounded : Icons.search_rounded,
      label: queryString,
      typed: typed,
      onTap: () {
        if (!shouldPlaySearchItemOnTap()) {
          _openResults(searchScreenController, queryString);
          return;
        }
        submitSearchQuery(
          queryString,
          onLink: (_) {
            Get.toNamed(ScreenNavigationSetup.searchResultScreen,
                id: ScreenNavigationSetup.id, arguments: queryString);
          },
          onRemember: searchScreenController.addToHistryQueryList,
          onOpenResults: (q) {
            Get.toNamed(ScreenNavigationSetup.searchResultScreen,
                id: ScreenNavigationSetup.id, arguments: q);
          },
          onAfterSubmit: GetPlatform.isDesktop
              ? searchScreenController.focusNode.unfocus
              : null,
          onPlayFailed: () => showSearchPlayFailed(context),
        );
      },
      onLongPress: () => _openResults(searchScreenController, queryString),
      trailing: IconButton(
        tooltip: isHistoryString ? 'clear'.tr : null,
        iconSize: 20,
        color: muted,
        onPressed: () => isHistoryString
            ? searchScreenController.removeQueryFromHistory(queryString)
            : searchScreenController.suggestionInput(queryString),
        icon: Icon(isHistoryString ? Icons.close_rounded : Icons.north_west),
      ),
    );
  }
}

/// One search list row: a round icon tile, the text, and a trailing action.
class SearchRow extends StatelessWidget {
  const SearchRow({
    super.key,
    required this.icon,
    required this.label,
    this.typed = '',
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String typed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final base = homeCardTitleStyle(context);
    final plain = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
        .copyWith(color: Theme.of(context).colorScheme.onSurface);
    // A suggestion that extends what was typed: typed part muted, the
    // completion bold — the eye goes straight to what is new.
    final prefix = typed.trim();
    final extendsTyped = prefix.isNotEmpty &&
        label.length > prefix.length &&
        label.toLowerCase().startsWith(prefix.toLowerCase());
    final text = extendsTyped
        ? Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: label.substring(0, prefix.length),
                  style: plain.copyWith(color: homeMutedColor(context))),
              TextSpan(text: label.substring(prefix.length)),
            ]),
            style: base,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text(label,
            style: plain, maxLines: 1, overflow: TextOverflow.ellipsis);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.only(
            left: HomeLayout.gutter,
            top: RiffSpacing.sm,
            right: HomeLayout.gutter - RiffSpacing.sm,
            bottom: RiffSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: homeTileColor(context),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: homeMutedColor(context)),
            ),
            const SizedBox(width: 14),
            Expanded(child: text),
            if (trailing != null) trailing! else const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
