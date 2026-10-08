import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/navigator.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// §5.8 pill search field: surface1 fill, no border at rest, 1 px accent
/// ring on focus, muted hint and leading search glyph. The Search screen's
/// field and [SearchLauncherField] share it.
InputDecoration searchFieldDecoration(BuildContext context,
    {Widget? suffixIcon}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  const pill = BorderRadius.all(Radius.circular(RiffRadii.pill));
  const restBorder =
      OutlineInputBorder(borderRadius: pill, borderSide: BorderSide.none);
  // Prefix/suffix keep their 48 dp slots so the text stays put.
  const iconSlot = BoxConstraints(
      minWidth: RiffSizes.touch, minHeight: RiffComponentSizes.searchField);
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: scheme.surfaceContainerLow,
    contentPadding: EdgeInsets.zero,
    hintText: "searchDes".tr,
    hintStyle:
        theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
    prefixIcon: Icon(Icons.search_rounded,
        size: RiffComponentSizes.trailingIcon, color: scheme.onSurfaceVariant),
    prefixIconConstraints: iconSlot,
    suffixIconConstraints: iconSlot,
    border: restBorder,
    enabledBorder: restBorder,
    disabledBorder: restBorder,
    focusedBorder: OutlineInputBorder(
      borderRadius: pill,
      borderSide: BorderSide(color: scheme.primary, width: 1),
    ),
    suffixIcon: suffixIcon,
  );
}

/// The search field's look without the typing: a tap opens the Search
/// screen (history, suggestions, results), where the real field takes
/// focus.
class SearchLauncherField extends StatelessWidget {
  const SearchLauncherField({super.key});

  static void openSearch() => Get.toNamed(ScreenNavigationSetup.searchScreen,
      id: ScreenNavigationSetup.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'search'.tr,
      excludeSemantics: true,
      child: SizedBox(
        height: RiffComponentSizes.searchField,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InputDecorator(
              decoration: searchFieldDecoration(context),
              isEmpty: true,
              textAlignVertical: TextAlignVertical.center,
              baseStyle: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
            // Over the fill, so the press ripple shows.
            const Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: StadiumBorder(),
                onTap: openSearch,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
