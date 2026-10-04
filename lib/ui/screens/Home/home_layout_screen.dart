import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
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
    final scheme = theme.colorScheme;
    final fg = shown ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: RiffSpacing.sm),
      child: Material(
        // Settings rows sit on the page background with a full-width
        // hairline along their bottom edge (Phase 8).
        color: Colors.transparent,
        shape: Border(bottom: BorderSide(color: theme.dividerColor, width: 0)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!shown),
          child: SizedBox(
            height: RiffComponentSizes.homeLayoutRow,
            child: Row(
              children: [
                const SizedBox(width: RiffSpacing.lg),
                Icon(section.icon,
                    size: RiffComponentSizes.headerIcon, color: fg),
                const SizedBox(width: RiffSpacing.md),
                Expanded(
                  child: Text(
                    section.labelKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(color: fg),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: RiffSpacing.md),
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
