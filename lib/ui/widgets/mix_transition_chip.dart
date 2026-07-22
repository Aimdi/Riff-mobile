import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/playlist_mix_service.dart';

/// Spotify-style "✨ Auto >" chip between playlist tracks in Mix mode.
class MixTransitionChip extends StatelessWidget {
  const MixTransitionChip({
    super.key,
    required this.style,
    required this.onTap,
  });

  final MixTransitionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final label = style == MixTransitionStyle.auto
        ? 'mixAuto'.tr
        : style.labelKey.tr;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withOpacity(0.55),
                        width: 1.2,
                      ),
                      color: accent.withOpacity(0.12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 16, color: accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<MixTransitionStyle?> showMixTransitionPicker(
  BuildContext context,
  MixTransitionStyle current,
) {
  return showModalBottomSheet<MixTransitionStyle>(
    context: context,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'mixChooseTransition'.tr,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...MixTransitionStyle.values.map((s) {
              final selected = s == current;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(s.labelKey.tr),
                subtitle: Text(_subtitleFor(s)),
                onTap: () => Navigator.pop(ctx, s),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

String _subtitleFor(MixTransitionStyle s) {
  switch (s) {
    case MixTransitionStyle.auto:
      return 'mixTransitionAutoDes'.tr;
    case MixTransitionStyle.fade:
      return 'mixTransitionFadeDes'.tr;
    case MixTransitionStyle.rise:
      return 'mixTransitionRiseDes'.tr;
    case MixTransitionStyle.blend:
      return 'mixTransitionBlendDes'.tr;
    case MixTransitionStyle.off:
      return 'mixTransitionOffDes'.tr;
  }
}
