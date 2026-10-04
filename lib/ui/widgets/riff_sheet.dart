import 'package:flutter/material.dart';

import '../screens/Home/home_layout.dart';
import '../utils/riff_tokens.dart';
import '/ui/theme/riff_spacing.dart';

/// Shared look for bottom sheets: a drag handle, an optional title, rows of
/// actions and an optional row of big quick actions. Every sheet in the app
/// (song menu, sleep timer, add to playlist, sort, …) is built from these so
/// they read as one family.

/// Shape for [showModalBottomSheet]: rounded top, like the player cards.
const riffSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
);

/// The pill at the top of a sheet.
class RiffSheetHandle extends StatelessWidget {
  const RiffSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.45),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Sheet title (and optional subtitle / trailing action).
class RiffSheetTitle extends StatelessWidget {
  const RiffSheetTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.xl,
          top: RiffSpacing.sm,
          right: RiffSpacing.md,
          bottom: RiffSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: fg)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One action row: icon, title, optional subtitle and trailing widget.
/// [destructive] tints it red (remove, delete, never play).
class RiffSheetTile extends StatelessWidget {
  const RiffSheetTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        theme.textTheme.titleMedium?.color ?? theme.colorScheme.onSurface;
    final fg = destructive ? theme.colorScheme.error : base;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 22, color: destructive ? fg : base.withOpacity(0.78)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: homeCardSubtitleStyle(context)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin separator between groups of rows.
class RiffSheetDivider extends StatelessWidget {
  const RiffSheetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.18),
      ),
    );
  }
}

/// A big square-ish action for the most common things (radio, play next,
/// add to playlist, share). Lay out several in [RiffQuickActions].
class RiffQuickAction {
  const RiffQuickAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class RiffQuickActions extends StatelessWidget {
  const RiffQuickActions(this.actions, {super.key});
  final List<RiffQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).textTheme.titleMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.lg, vertical: RiffSpacing.sm),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: homeTileColor(context),
                borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: actions[i].onTap,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(actions[i].icon, size: 24, color: fg),
                        const SizedBox(height: 6),
                        Text(actions[i].label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small rounded chip, for choices inside a sheet (sleep timer lengths,
/// "open in" targets, …).
class RiffChoiceChip extends StatelessWidget {
  const RiffChoiceChip(
      {super.key,
      required this.label,
      required this.onTap,
      this.icon,
      this.selected = false});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final fg = selected
        ? theme.colorScheme.onPrimary
        : (theme.textTheme.titleMedium?.color ?? theme.colorScheme.onSurface);
    return Material(
      color: selected ? accent : homeTileColor(context),
      shape: StadiumBorder(
          side: selected ? BorderSide.none : homeTileBorder(context)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: theme.textTheme.labelMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
