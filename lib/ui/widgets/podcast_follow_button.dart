import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

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
    // §5.5: Subscribe = primary pill, Subscribed = outline pill; colours
    // come from the button themes.
    final pad = EdgeInsets.symmetric(
      horizontal: compact ? RiffSpacing.md : RiffSpacing.lg,
      vertical: compact ? RiffSpacing.xs : RiffSpacing.sm,
    );
    final iconSize = compact
        ? RiffComponentSizes.chipLeadingIcon
        : RiffComponentSizes.chipChevron;

    if (following) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.check, size: iconSize),
        label: Text('subscribed'.tr),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: pad,
          shape: const StadiumBorder(),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.add, size: iconSize),
      label: Text('subscribe'.tr),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: pad,
        shape: const StadiumBorder(),
      ),
    );
  }
}
