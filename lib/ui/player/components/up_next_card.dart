import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// The full player's collapsed queue: a slim one-line tab standing on the
/// bottom edge, rounded on top, as wide as the player's content above it. It runs
/// down through the system inset; its label stays above it. The whole
/// strip, the tab and the gap beside it, opens the queue, so a tap never
/// reaches the hidden queue underneath.
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    super.key,
    required this.preview,
    required this.bottomInset,
    required this.onTap,
  });

  /// Height of the strip above the system inset.
  static const double extent = RiffComponentSizes.queueCard;

  /// "First title · N more"; empty when nothing comes next.
  final String preview;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: RiffComponentSizes.queueCardMaxWidth),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(RiffRadii.lg)),
                side: BorderSide(color: theme.dividerColor, width: 0),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  height: RiffComponentSizes.queueCard + bottomInset,
                  padding: EdgeInsets.only(
                      left: RiffSpacing.lg,
                      right: RiffSpacing.lg,
                      bottom: bottomInset),
                  alignment: Alignment.center,
                  // One line: an up-arrow (pull me up), then "Up Next ·
                  // next song".
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.keyboard_arrow_up_rounded,
                          size: RiffComponentSizes.trailingIcon, color: muted),
                      const SizedBox(width: RiffSpacing.xs),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: 'upNext'.tr,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: muted),
                            ),
                            if (preview.isNotEmpty) ...[
                              TextSpan(
                                text: ' · ',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: muted),
                              ),
                              TextSpan(
                                text: preview,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface),
                              ),
                            ],
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
