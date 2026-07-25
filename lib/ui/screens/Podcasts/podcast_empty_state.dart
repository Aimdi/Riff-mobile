import 'package:flutter/material.dart';

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
    final dim = theme.textTheme.bodySmall?.color;
    return Center(
      child: Padding(
        // Extra bottom padding lifts the block optically above the mini
        // player instead of letting it sit low in the leftover space.
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: dim?.withOpacity(0.4)),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: dim?.withOpacity(0.75), height: 1.4),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
