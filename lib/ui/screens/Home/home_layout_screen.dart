import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/utils/riff_tokens.dart';
import '../../widgets/cust_switch.dart';
import 'home_layout.dart';
import 'home_sections.dart';

/// "Home layout": switch off the Home sections you don't want. The order
/// is fixed — your own music first, the YouTube feed after.
class HomeLayoutScreen extends StatelessWidget {
  const HomeLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    HomeSectionPrefs.ensureLoaded();
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiffPageHeader(
            'homeLayout'.tr,
            subtitle: 'homeLayoutDes'.tr,
            actions: [
              Obx(() {
                // Reads the observable order and hidden set.
                final isDefault = HomeSectionPrefs.isDefault;
                return TextButton(
                  onPressed: isDefault ? null : HomeSectionPrefs.reset,
                  child: Text('reset'.tr),
                );
              }),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter + RiffSpacing.xs,
                top: RiffSpacing.xxs,
                right: HomeLayout.gutter,
                bottom: RiffSpacing.sm),
            child: Text('homeLayoutHint'.tr,
                style: homeCardSubtitleStyle(context)),
          ),
          Expanded(
            child: Obx(() {
              final hidden = HomeSectionPrefs.hidden.toSet();
              return ListView(
                padding: const EdgeInsets.only(
                    left: HomeLayout.gutter,
                    right: HomeLayout.gutter,
                    bottom: RiffSpacing.listEnd),
                children: [
                  for (final section in switchableHomeSections)
                    _SectionRow(
                      key: ValueKey(section),
                      section: section,
                      shown: !hidden.contains(section),
                      onChanged: (v) => HomeSectionPrefs.setHidden(section, !v),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    super.key,
    required this.section,
    required this.shown,
    required this.onChanged,
  });
  final HomeSection section;
  final bool shown;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.textTheme.titleMedium?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
          side: homeTileBorder(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!shown),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(section.icon,
                    size: 22,
                    color: shown
                        ? theme.colorScheme.secondary
                        : homeMutedColor(context)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    section.labelKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: shown ? fg : homeMutedColor(context)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CustSwitch(value: shown, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
