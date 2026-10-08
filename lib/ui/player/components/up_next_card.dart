import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';

/// The full player's collapsed queue: a slim floating card in the mini
/// player's style (rounded, hairline edge, clear of the system inset), as
/// wide as the player's content above it. The whole strip, the card and
/// the gap around it, opens the queue, so a tap never reaches the hidden
/// queue underneath.
class UpNextCard extends StatelessWidget {
  const UpNextCard({
    super.key,
    required this.preview,
    required this.bottomInset,
    required this.onTap,
  });

  /// Height of the strip above the system inset: the card and the gap
  /// below it.
  static const double extent = RiffComponentSizes.queueCard + RiffSpacing.sm;

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
        padding: EdgeInsets.only(
          left: RiffSpacing.xxl,
          right: RiffSpacing.xxl,
          bottom: RiffSpacing.sm + bottomInset,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: RiffComponentSizes.queueCardMaxWidth),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RiffRadii.miniPlayer),
                side: BorderSide(color: theme.dividerColor, width: 0),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: double.infinity,
                  height: RiffComponentSizes.queueCard,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: RiffComponentSizes.handleWidth,
                        height: RiffComponentSizes.handleHeight,
                        decoration: BoxDecoration(
                          color: RiffColors.of(context).handle,
                          borderRadius: BorderRadius.circular(RiffRadii.pill),
                        ),
                      ),
                      const SizedBox(height: RiffSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: RiffSpacing.lg),
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
