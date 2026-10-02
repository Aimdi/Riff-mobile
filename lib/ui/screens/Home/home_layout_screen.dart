import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/utils/riff_tokens.dart';
import '../../widgets/cust_switch.dart';
import 'home_layout.dart';
import 'home_sections.dart';

/// "Home layout": drag the sections into the order you want, switch off
/// the ones you don't. The same idea as Echo Music's ordered home
/// sections, but the order is yours.
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
            padding: const EdgeInsets.fromLTRB(
                HomeLayout.gutter + 4, 2, HomeLayout.gutter, 8),
            child: Text('homeLayoutHint'.tr,
                style: homeCardSubtitleStyle(context).copyWith(fontSize: 13)),
          ),
          Expanded(
            child: Obx(() {
              final order = HomeSectionPrefs.order.toList();
              final hidden = HomeSectionPrefs.hidden;
              return ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    HomeLayout.gutter, 0, HomeLayout.gutter, 200),
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
                  child: child,
                ),
                itemCount: order.length,
                onReorder: HomeSectionPrefs.reorder,
                itemBuilder: (context, i) {
                  final section = order[i];
                  final shown = !hidden.contains(section);
                  return _SectionRow(
                    key: ValueKey(section),
                    index: i,
                    section: section,
                    shown: shown,
                    onChanged: (v) => HomeSectionPrefs.setHidden(section, !v),
                  );
                },
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
    required this.index,
    required this.section,
    required this.shown,
    required this.onChanged,
  });
  final int index;
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
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Icon(Icons.drag_indicator_rounded,
                    color: homeMutedColor(context)),
              ),
            ),
            Icon(section.icon,
                size: 22,
                color: shown ? theme.colorScheme.secondary : homeMutedColor(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                section.labelKey.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: shown ? fg : homeMutedColor(context)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CustSwitch(value: shown, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}
