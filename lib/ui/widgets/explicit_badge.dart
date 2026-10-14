import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_tokens.dart';

/// The "E" Spotify, Apple Music and YouTube Music put before an explicit
/// song's artist: a small rounded square in the secondary text colour with
/// the letter in the page colour. Read as "Explicit".
class ExplicitBadge extends StatelessWidget {
  const ExplicitBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'explicit'.tr,
      child: ExcludeSemantics(
        child: Container(
          width: RiffComponentSizes.explicitBadge,
          height: RiffComponentSizes.explicitBadge,
          padding: const EdgeInsets.all(RiffComponentSizes.explicitBadgeInset),
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant,
            borderRadius:
                BorderRadius.circular(RiffComponentSizes.explicitBadgeRadius),
          ),
          child: FittedBox(
            child: Text(
              'E',
              style:
                  theme.textTheme.labelSmall?.copyWith(color: scheme.surface),
            ),
          ),
        ),
      ),
    );
  }
}
