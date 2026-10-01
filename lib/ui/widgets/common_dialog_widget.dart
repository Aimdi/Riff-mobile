import 'package:flutter/material.dart';

import '../screens/Home/home_layout.dart';
import '../utils/theme_controller.dart';

class CommonDialog extends StatelessWidget {
  const CommonDialog({super.key, this.child, this.maxWidth = 500});
  final double maxWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: child,
          )),
    );
  }
}

/// Dialog heading: an optional accent icon badge over a bold title, the
/// same family as the sheet titles.
class RiffDialogTitle extends StatelessWidget {
  const RiffDialogTitle(this.title, {super.key, this.icon, this.subtitle});
  final String title;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color ?? RiffSurfaces.textPrimary;
    final accent = theme.colorScheme.secondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(height: 12),
        ],
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: fg)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle!,
              textAlign: TextAlign.center,
              style: homeCardSubtitleStyle(context)),
        ],
      ],
    );
  }
}

/// Full-width dialog button: accent-filled for the main action, a quiet
/// text button otherwise. A null [onPressed] keeps the space but hides the
/// label (for "working…" states).
class RiffDialogButton extends StatelessWidget {
  const RiffDialogButton(this.label,
      {super.key, required this.onPressed, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color ?? RiffSurfaces.textPrimary;
    const shape = StadiumBorder();
    final text = Text(label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
    if (!primary) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
            foregroundColor: fg,
            minimumSize: const Size.fromHeight(46),
            shape: shape),
        child: text,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.secondary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: homeTileColor(context),
          minimumSize: const Size.fromHeight(48),
          shape: shape),
      child: text,
    );
  }
}
