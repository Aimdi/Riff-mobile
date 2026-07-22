import 'package:flutter/material.dart';

/// Flat settings group that matches Library / Plugins — large section label,
/// accent icon, no tinted card chrome.
class CustomExpansionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const CustomExpansionTile({
    super.key,
    required this.children,
    required this.icon,
    required this.title,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final muted = theme.textTheme.bodyMedium?.color?.withOpacity(0.55);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            childrenPadding: const EdgeInsets.only(left: 4, right: 4, bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            shape: const Border(),
            collapsedShape: const Border(),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            iconColor: muted,
            collapsedIconColor: muted,
            textColor: theme.textTheme.titleMedium?.color,
            collapsedTextColor: theme.textTheme.titleMedium?.color,
            leading: Icon(icon, color: accent, size: 22),
            title: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
            children: children,
          ),
          Divider(
            height: 1,
            thickness: 0.6,
            indent: 4,
            endIndent: 4,
            color: theme.dividerColor.withOpacity(0.35),
          ),
        ],
      ),
    );
  }
}
