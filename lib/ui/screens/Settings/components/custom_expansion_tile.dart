import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '../../../utils/riff_tokens.dart';
import '../../Home/home_layout.dart';
import '../settings_screen_controller.dart';

/// Muted, smaller description line under a setting's title.
TextStyle settingsSubtitleStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: homeMutedColor(context),
    );

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

/// A settings group: a card with a tinted icon, title and one-line summary
/// that expands to its settings. While Settings search has text, the group
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
    final accent = theme.colorScheme.secondary;
    final header = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent, size: 21),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if ((subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
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
      // Tiles carry a 5dp inset of their own.
      padding: const EdgeInsets.only(
          left: RiffSpacing.sm, right: RiffSpacing.xs, bottom: RiffSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
          side: homeTileBorder(context),
        ),
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
                  iconColor: homeMutedColor(context),
                  collapsedIconColor: homeMutedColor(context),
                  title: header,
                  children: [body],
                ),
              ),
      ),
    );
  }
}
