import 'package:flutter/material.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// Shared look for bottom sheets: a drag handle, an optional title, rows of
/// actions and an optional row of big quick actions. Every sheet in the app
/// (song menu, sleep timer, add to playlist, sort, …) is built from these so
/// they read as one family.

/// Shape for [showModalBottomSheet]: the theme's 16dp rounded top (§5.10).
const riffSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(RiffRadii.lg)),
);

/// The pill at the top of a sheet: 36 × 4, 8dp from the top (§5.10).
class RiffSheetHandle extends StatelessWidget {
  const RiffSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: RiffComponentSizes.handleWidth,
        height: RiffComponentSizes.handleHeight,
        margin:
            const EdgeInsets.only(top: RiffSpacing.sm, bottom: RiffSpacing.sm),
        decoration: BoxDecoration(
          color: RiffColors.of(context).handle,
          borderRadius: BorderRadius.circular(RiffRadii.pill),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.lg,
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
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: theme.colorScheme.onSurface)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: RiffSpacing.xxs),
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
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

/// One action row (§5.10): min height 52, 16dp sides, 22dp icon and a
/// bodyLarge label in the primary text colour, optional subtitle and
/// trailing widget. [destructive] tints it red (remove, delete, never play).
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
    final fg =
        destructive ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: RiffComponentSizes.sheetRow),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: RiffSpacing.lg, vertical: RiffSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: RiffComponentSizes.sheetIcon, color: fg),
              const SizedBox(width: RiffSpacing.lg),
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
                        padding: const EdgeInsets.only(top: RiffSpacing.xxs),
                        child: Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: RiffSpacing.sm),
                trailing!
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width hairline between groups of rows (§5.10). Keeps its 9dp
/// footprint; the line itself is one physical pixel in the divider colour.
class RiffSheetDivider extends StatelessWidget {
  const RiffSheetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: RiffSpacing.xs),
      child: Divider(height: 1),
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
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.lg, vertical: RiffSpacing.sm),
      // Equal-height tiles: the row is as tall as its tallest label.
      child: IntrinsicHeight(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: RiffSpacing.sm),
            Expanded(
              child: Material(
                // One step above the sheet's surface1, flat, radius 8.
                color: RiffColors.of(context).surface2,
                borderRadius: BorderRadius.circular(RiffRadii.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: actions[i].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: RiffSpacing.md, horizontal: RiffSpacing.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(actions[i].icon,
                            size: RiffComponentSizes.sheetQuickIcon, color: fg),
                        const SizedBox(height: RiffSpacing.xs),
                        Text(actions[i].label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: fg)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      )),
    );
  }
}

/// Small pill chip, for choices inside a sheet (sleep timer lengths,
/// "open in" targets, …). Styled per §5.6: 32 tall, 12dp sides, divider
/// outline; selected = accentMuted fill, accent outline and text.
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
    final fg = selected ? accent : theme.colorScheme.onSurface;
    return Material(
      color: selected ? RiffColors.of(context).accentMuted : Colors.transparent,
      shape: StadiumBorder(
          side: BorderSide(color: selected ? accent : theme.dividerColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RiffSizes.chipHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: RiffComponentSizes.chipLeadingIcon, color: fg),
                  const SizedBox(width: RiffSpacing.xs),
                ],
                Text(label,
                    style: theme.textTheme.labelMedium?.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
