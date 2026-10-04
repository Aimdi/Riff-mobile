import 'package:flutter/material.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// The app's dialog frame. Background, 16dp radius, barrier and text
/// styles come from the theme's [DialogTheme] (§5.11).
class CommonDialog extends StatelessWidget {
  const CommonDialog({super.key, this.child, this.maxWidth = 500});
  final double maxWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Dialog(child: child)),
    );
  }
}

/// Dialog heading: an optional icon badge over a titleLarge title, the
/// same family as the sheet titles. The badge is a flat surface2 circle
/// (the accent is kept for interactive things, §2.5).
class RiffDialogTitle extends StatelessWidget {
  const RiffDialogTitle(this.title, {super.key, this.icon, this.subtitle});
  final String title;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Container(
            width: RiffComponentSizes.dialogBadge,
            height: RiffComponentSizes.dialogBadge,
            decoration: BoxDecoration(
              color: RiffColors.of(context).surface2,
              shape: BoxShape.circle,
            ),
            child:
                Icon(icon, color: fg, size: RiffComponentSizes.dialogBadgeIcon),
          ),
          const SizedBox(height: RiffSpacing.md),
        ],
        Text(title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(color: fg)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: RiffSpacing.xs),
          // Dialog body text: primary colour on surface1 (§5.11).
          Text(subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
        ],
      ],
    );
  }
}

/// Full-width dialog button (§5.5): a pill [FilledButton] for the main
/// action, a [TextButton] otherwise; colours and text from the button
/// themes. A null [onPressed] keeps the space but hides the label (for
/// "working…" states).
class RiffDialogButton extends StatelessWidget {
  const RiffDialogButton(this.label,
      {super.key, required this.onPressed, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final text = Text(label);
    const size = Size.fromHeight(RiffComponentSizes.button);
    if (!primary) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(minimumSize: size),
        child: text,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: size),
      child: text,
    );
  }
}
