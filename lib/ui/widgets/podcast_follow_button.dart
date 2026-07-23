import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shared podcast Follow control — matches the RSS show header:
/// green filled **+ Follow** pill, or outlined **✓ Following**.
class PodcastFollowButton extends StatelessWidget {
  const PodcastFollowButton({
    super.key,
    required this.following,
    required this.onPressed,
    this.compact = false,
  });

  final bool following;
  final VoidCallback? onPressed;

  /// Slightly tighter padding for list-row trailing slots.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? 12 : 14,
      vertical: compact ? 6 : 8,
    );

    if (following) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.check, size: compact ? 16 : 18, color: accent),
        label: Text('subscribed'.tr),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withOpacity(0.55)),
          visualDensity: VisualDensity.compact,
          padding: pad,
          shape: const StadiumBorder(),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.add, size: compact ? 16 : 18),
      label: Text('subscribe'.tr),
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.black,
        visualDensity: VisualDensity.compact,
        padding: pad,
        shape: const StadiumBorder(),
      ),
    );
  }
}
