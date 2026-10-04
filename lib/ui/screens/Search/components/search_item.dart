import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/screens/Search/search_play_top.dart';
import '/ui/screens/Search/search_screen_controller.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
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
        iconSize: RiffComponentSizes.trailingIcon,
        color: muted,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(RiffComponentSizes.iconHit),
        ),
        onPressed: () => isHistoryString
            ? searchScreenController.removeQueryFromHistory(queryString)
            : searchScreenController.suggestionInput(queryString),
        icon: Icon(isHistoryString ? Icons.close_rounded : Icons.north_west),
      ),
    );
  }
}

/// One search list row (§5.2): the leading glyph, the text, and a trailing
/// action, with a full-width hairline drawn inside the bottom edge.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface);
    final plain = theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface);
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
                  style: plain?.copyWith(color: scheme.onSurfaceVariant)),
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
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              top: RiffSpacing.md,
              right: HomeLayout.gutter - RiffSpacing.sm,
              bottom: RiffSpacing.md),
          child: Row(
            children: [
              SizedBox.square(
                dimension: RiffComponentSizes.iconHit,
                child: Icon(icon,
                    size: RiffComponentSizes.trailingIcon,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: RiffSpacing.md),
              Expanded(child: text),
              if (trailing != null)
                trailing!
              else
                const SizedBox(height: RiffComponentSizes.iconHit),
            ],
          ),
        ),
      ),
    );
  }
}
