import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../navigator.dart';
import '../../widgets/riff_sheet.dart';

/// The blocks Home is built from. Echo Music keeps the same idea as a
/// `HomeSection` list rendered in order; here the order and the hidden set
/// are the user's, kept in AppPrefs.
enum HomeSection {
  chips('homeSectionChips', Icons.tune_rounded),
  resume('continueListening', Icons.play_circle_outline_rounded),
  quickPicks('quickpicks', Icons.view_carousel_outlined),
  speedDial('speedDial', Icons.grid_view_rounded),
  riffWave('riffWave', Icons.graphic_eq_rounded),
  generators('homeSectionGenerators', Icons.auto_awesome_outlined),
  dailyMixes('dailyMixes', Icons.blender_outlined),
  shelves('homeSectionShelves', Icons.view_agenda_outlined),
  yourWeek('yourWeek', Icons.bar_chart_rounded);

  const HomeSection(this.labelKey, this.icon);

  /// Localisation key of the section's name.
  final String labelKey;
  final IconData icon;

  static HomeSection? byName(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Default order: your stuff first, then the picks, then YouTube's feed.
const defaultHomeSectionOrder = [
  HomeSection.chips,
  HomeSection.resume,
  HomeSection.quickPicks,
  HomeSection.speedDial,
  HomeSection.riffWave,
  HomeSection.generators,
  HomeSection.dailyMixes,
  HomeSection.shelves,
  HomeSection.yourWeek,
];

/// Turns a stored list of section names back into a full order: unknown
/// names are dropped, duplicates collapse, and sections the stored list
/// doesn't know yet (added in a later version) are appended in default
/// order so nothing silently disappears.
List<HomeSection> parseHomeSectionOrder(dynamic stored) {
  final out = <HomeSection>[];
  if (stored is List) {
    for (final name in stored) {
      final s = HomeSection.byName('$name');
      if (s != null && !out.contains(s)) out.add(s);
    }
  }
  for (final s in defaultHomeSectionOrder) {
    if (!out.contains(s)) out.add(s);
  }
  return out;
}

Set<HomeSection> parseHiddenHomeSections(dynamic stored) {
  if (stored is! List) return const {};
  return {
    for (final name in stored)
      if (HomeSection.byName('$name') != null) HomeSection.byName('$name')!,
  };
}

/// The user's Home layout: observable order and hidden set, persisted in
/// the AppPrefs box when it is open (tests and the first frame before Hive
/// is ready just see the defaults).
class HomeSectionPrefs {
  HomeSectionPrefs._();

  static const orderKey = 'homeSectionOrder';
  static const hiddenKey = 'homeSectionHidden';

  static final order = RxList<HomeSection>(defaultHomeSectionOrder);
  static final hidden = RxSet<HomeSection>();
  static bool _loaded = false;

  static Box? get _box =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// Reads the stored layout once; safe to call on every build.
  static void ensureLoaded() {
    if (_loaded) return;
    final box = _box;
    if (box == null) return;
    _loaded = true;
    order.assignAll(parseHomeSectionOrder(box.get(orderKey)));
    hidden.assignAll(parseHiddenHomeSections(box.get(hiddenKey)));
  }

  /// Sections to draw, in order.
  static List<HomeSection> get visible =>
      order.where((s) => !hidden.contains(s)).toList();

  static bool get isDefault =>
      hidden.isEmpty && _sameOrder(order, defaultHomeSectionOrder);

  static bool _sameOrder(List<HomeSection> a, List<HomeSection> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _save() {
    final box = _box;
    if (box == null) return;
    box.put(orderKey, order.map((s) => s.name).toList());
    box.put(hiddenKey, hidden.map((s) => s.name).toList());
  }

  static void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final s = order.removeAt(oldIndex);
    order.insert(newIndex, s);
    _save();
  }

  /// Moves [section] one step among the *visible* sections, so "move up"
  /// on Home hops over hidden ones the way the user sees it.
  static void move(HomeSection section, int delta) {
    final shown = visible;
    final at = shown.indexOf(section);
    if (at < 0) return;
    final target = (at + delta).clamp(0, shown.length - 1);
    if (target == at) return;
    final neighbour = shown[target];
    order.remove(section);
    final insertAt = order.indexOf(neighbour) + (delta > 0 ? 1 : 0);
    order.insert(insertAt, section);
    _save();
  }

  static void setHidden(HomeSection section, bool value) {
    if (value) {
      hidden.add(section);
    } else {
      hidden.remove(section);
    }
    _save();
  }

  static void reset() {
    order.assignAll(defaultHomeSectionOrder);
    hidden.clear();
    _save();
  }
}

/// Long-press menu on a Home section: move it, hide it, or open the full
/// layout page.
Future<void> showHomeSectionSheet(BuildContext context, HomeSection section) {
  final shown = HomeSectionPrefs.visible;
  final at = shown.indexOf(section);
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
          if (at > 0)
            RiffSheetTile(
              icon: Icons.arrow_upward_rounded,
              title: 'moveUp'.tr,
              onTap: () {
                Navigator.of(sheet).pop();
                HomeSectionPrefs.move(section, -1);
              },
            ),
          if (at >= 0 && at < shown.length - 1)
            RiffSheetTile(
              icon: Icons.arrow_downward_rounded,
              title: 'moveDown'.tr,
              onTap: () {
                Navigator.of(sheet).pop();
                HomeSectionPrefs.move(section, 1);
              },
            ),
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
  const HomeSectionSlot({super.key, required this.section, required this.child});
  final HomeSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => showHomeSectionSheet(context, section),
      child: child,
    );
  }
}
