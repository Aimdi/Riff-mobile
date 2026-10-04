import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../../Home/home_layout.dart';
import '../settings_screen_controller.dart';

/// Muted, smaller description line under a setting's title.
TextStyle settingsSubtitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: homeMutedColor(context),
    );

/// Content padding of a setting row inside a group (the group body adds
/// the rest, so rows line up 12dp in from the group's edges).
const settingsTilePadding =
    EdgeInsets.only(left: RiffSpacing.xs, right: RiffSpacing.sm);

/// Marks a setting whose tile is built inside an Obx (so its text can't be
/// read up front) with the words search should match.
class SettingsSearchable extends StatelessWidget {
  const SettingsSearchable({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  bool matches(String q) =>
      title.toLowerCase().contains(q) ||
      (subtitle?.toLowerCase().contains(q) ?? false);

  @override
  Widget build(BuildContext context) => child;
}

String? _textOf(Widget? w) {
  if (w is Text) return w.data ?? w.textSpan?.toPlainText();
  return null;
}

/// Whether [w] matches [q]: true / false for tiles whose text is known,
/// null for anything else (shown only when the section itself matches).
@visibleForTesting
bool? settingsChildMatches(Widget w, String q) {
  if (w is SettingsSearchable) return w.matches(q);
  if (w is ListTile) {
    final texts = [_textOf(w.title), _textOf(w.subtitle)];
    if (texts.every((t) => t == null)) return null;
    return texts.any((t) => t != null && t.toLowerCase().contains(q));
  }
  return null;
}

/// A settings group: an icon, title (titleLarge) and one-line summary that
/// expands to its settings, on the page background with a hairline along
/// its bottom edge (Phase 8). Rows inside get bodyLarge titles, bodyMedium
/// subtitles and a 52dp minimum height. While Settings search has text, the group
/// opens by itself and shows only matching settings (or hides entirely).
class CustomExpansionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const CustomExpansionTile({
    super.key,
    required this.children,
    required this.icon,
    required this.title,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<SettingsScreenController>()) {
      return _card(context, children, searching: false);
    }
    final c = Get.find<SettingsScreenController>();
    return Obx(() {
      final q = c.settingsSearch.value.trim().toLowerCase();
      if (q.isEmpty) return _card(context, children, searching: false);
      final sectionMatches = title.toLowerCase().contains(q) ||
          (subtitle?.toLowerCase().contains(q) ?? false);
      final visible = children
          .where((w) => settingsChildMatches(w, q) ?? sectionMatches)
          .toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      return _card(context, visible, searching: true);
    });
  }

  Widget _card(BuildContext context, List<Widget> items,
      {required bool searching}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final header = Row(
      children: [
        Container(
          width: RiffComponentSizes.settingsGroupIcon,
          height: RiffComponentSizes.settingsGroupIcon,
          alignment: Alignment.center,
          child: Icon(icon,
              color: scheme.onSurface, size: RiffComponentSizes.headerIcon),
        ),
        const SizedBox(width: RiffSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if ((subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: RiffSpacing.xxs),
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: settingsSubtitleStyle(context)),
              ],
            ],
          ),
        ),
      ],
    );
    final body = Padding(
      // Tiles carry [settingsTilePadding] of their own.
      padding: const EdgeInsets.only(
          left: RiffSpacing.sm, right: RiffSpacing.xs, bottom: RiffSpacing.sm),
      child: ListTileTheme.merge(
        titleTextStyle: theme.textTheme.bodyLarge,
        subtitleTextStyle: theme.textTheme.bodyMedium,
        iconColor: scheme.onSurfaceVariant,
        minTileHeight: RiffComponentSizes.settingsRow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: RiffSpacing.sm),
      child: Material(
        // On the page background; the hairline along the bottom edge
        // separates the groups.
        color: Colors.transparent,
        shape: Border(bottom: BorderSide(color: theme.dividerColor, width: 0)),
        clipBehavior: Clip.antiAlias,
        child: searching
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        left: RiffSpacing.lg,
                        top: RiffSpacing.md,
                        right: RiffSpacing.lg,
                        bottom: RiffSpacing.sm),
                    child: header,
                  ),
                  body,
                ],
              )
            : Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: initiallyExpanded,
                  tilePadding: const EdgeInsets.only(
                      left: RiffSpacing.lg,
                      top: RiffSpacing.sm,
                      right: RiffSpacing.md,
                      bottom: RiffSpacing.sm),
                  childrenPadding: EdgeInsets.zero,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  iconColor: scheme.onSurfaceVariant,
                  collapsedIconColor: scheme.onSurfaceVariant,
                  title: header,
                  children: [body],
                ),
              ),
      ),
    );
  }
}
