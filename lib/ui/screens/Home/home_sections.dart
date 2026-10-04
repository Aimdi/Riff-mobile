import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../navigator.dart';
import '../../widgets/riff_sheet.dart';
import 'home_feed_builder.dart';

export 'home_feed_builder.dart' show HomeSection;

/// Sections the user can switch off (Settings → Home layout, or a long
/// press on the section). The order itself is fixed: your own music
/// first, the YouTube feed after.
const switchableHomeSections = [
  HomeSection.jumpBackIn,
  HomeSection.riffWave,
  HomeSection.speedDial,
  HomeSection.quickPicks,
  HomeSection.personalized,
  HomeSection.yourWeek,
  HomeSection.editorial,
];

extension HomeSectionLabels on HomeSection {
  /// Localisation key of the section's name.
  String get labelKey => switch (this) {
        HomeSection.header => 'home',
        HomeSection.jumpBackIn => 'jumpBackIn',
        HomeSection.riffWave => 'riffWave',
        HomeSection.speedDial => 'speedDial',
        HomeSection.quickPicks => 'quickpicks',
        HomeSection.personalized => 'homeSectionPersonal',
        HomeSection.yourWeek => 'yourWeek',
        HomeSection.editorial => 'homeSectionShelves',
        HomeSection.exploreMore => 'exploreMore',
      };

  IconData get icon => switch (this) {
        HomeSection.header => Icons.home_rounded,
        HomeSection.jumpBackIn => Icons.play_circle_outline_rounded,
        HomeSection.riffWave => Icons.graphic_eq_rounded,
        HomeSection.speedDial => Icons.grid_view_rounded,
        HomeSection.quickPicks => Icons.view_carousel_outlined,
        HomeSection.personalized => Icons.blender_outlined,
        HomeSection.yourWeek => Icons.bar_chart_rounded,
        HomeSection.editorial => Icons.view_agenda_outlined,
        HomeSection.exploreMore => Icons.explore_outlined,
      };
}

/// Stored names from before the fixed order (1.7.132 and older) mapped to
/// today's sections; chips and generators are gone (one chip row under
/// Riff Wave now).
const _legacyNames = {
  'resume': HomeSection.jumpBackIn,
  'dailyMixes': HomeSection.personalized,
  'shelves': HomeSection.editorial,
};

HomeSection? _byName(String name) {
  final legacy = _legacyNames[name];
  if (legacy != null) return legacy;
  for (final s in switchableHomeSections) {
    if (s.name == name) return s;
  }
  return null;
}

Set<HomeSection> parseHiddenHomeSections(dynamic stored) {
  if (stored is! List) return const {};
  return {
    for (final name in stored)
      if (_byName('$name') != null) _byName('$name')!,
  };
}

/// Which Home sections are switched off, persisted in AppPrefs when it is
/// open (tests and the first frame before Hive is ready see none hidden).
class HomeSectionPrefs {
  HomeSectionPrefs._();

  static const hiddenKey = 'homeSectionHidden';

  static final hidden = RxSet<HomeSection>();
  static bool _loaded = false;

  static Box? get _box =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Reads the stored set once; safe to call on every build.
  static void ensureLoaded() {
    if (_loaded) return;
    final box = _box;
    if (box == null) return;
    _loaded = true;
    hidden.assignAll(parseHiddenHomeSections(box.get(hiddenKey)));
    // The custom order from older versions no longer applies.
    box.delete('homeSectionOrder');
  }

  static bool get isDefault => hidden.isEmpty;

  static void _save() =>
      _box?.put(hiddenKey, hidden.map((s) => s.name).toList());

  static void setHidden(HomeSection section, bool value) {
    if (value) {
      hidden.add(section);
    } else {
      hidden.remove(section);
    }
    _save();
  }

  static void reset() {
    hidden.clear();
    _save();
  }
}

/// Long-press menu on a Home section: hide it, or open the layout page.
Future<void> showHomeSectionSheet(BuildContext context, HomeSection section) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    constraints: const BoxConstraints(maxWidth: 500),
    shape: riffSheetShape,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RiffSheetHandle(),
          RiffSheetTitle(section.labelKey.tr),
          RiffSheetTile(
            icon: Icons.visibility_off_outlined,
            title: 'hideSection'.tr,
            subtitle: 'hideSectionDes'.tr,
            onTap: () {
              Navigator.of(sheet).pop();
              HomeSectionPrefs.setHidden(section, true);
            },
          ),
          const RiffSheetDivider(),
          RiffSheetTile(
            icon: Icons.dashboard_customize_outlined,
            title: 'homeLayout'.tr,
            onTap: () {
              Navigator.of(sheet).pop();
              Get.toNamed(ScreenNavigationSetup.homeLayoutScreen,
                  id: ScreenNavigationSetup.id);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Wraps one Home section so a long press anywhere on it (that nothing
/// inside claims first) opens [showHomeSectionSheet].
class HomeSectionSlot extends StatelessWidget {
  const HomeSectionSlot(
      {super.key, required this.section, required this.child});
  final HomeSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!switchableHomeSections.contains(section)) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => showHomeSectionSheet(context, section),
      child: child,
    );
  }
}
