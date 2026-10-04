import 'package:flutter/material.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// Consistent empty state for the Podcasts tabs: centered icon + message +
/// optional action (usually a jump to Discover). Replaces the bare text
/// lines that floated at different heights on the Queue and Subs tabs.
class PodcastEmptyState extends StatelessWidget {
  const PodcastEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.actionIcon = Icons.explore_outlined,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        // Extra bottom padding lifts the block optically above the mini
        // player instead of letting it sit low in the leftover space.
        padding: const EdgeInsets.only(
            left: RiffSpacing.x3l,
            top: RiffSpacing.xxl,
            right: RiffSpacing.x3l,
            bottom: RiffSpacing.unit * 23),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: RiffComponentSizes.emptyStateIcon, color: muted),
            const SizedBox(height: RiffSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: RiffSpacing.lg),
              // Secondary pill from the theme (§5.5).
              OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: RiffComponentSizes.trailingIcon),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
