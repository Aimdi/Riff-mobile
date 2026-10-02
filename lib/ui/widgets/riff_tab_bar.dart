import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/navigator.dart';
import '/ui/player/components/mini_player.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Home/home_screen_controller.dart';

/// Phone shell geometry, Echo Music style: a floating tab bar pill at the
/// bottom with the mini player docked above it, both hidden as the player
/// opens. Wider screens keep the side rail and the full-width mini player.
class RiffShell {
  RiffShell._();

  static const tabBarHeight = 60.0;
  static const tabBarGap = 10.0;
  static const miniPlayerHeight = 75.0;

  /// Below this width the rail goes and the dock takes over.
  static const phoneWidth = 600.0;

  /// Tests on a desktop host set this to pretend to be a phone.
  @visibleForTesting
  static bool? desktopOverride;

  static bool get _desktop => desktopOverride ?? GetPlatform.isDesktop;

  static bool usesDock(double width) => width < phoneWidth && !_desktop;

  static bool usesDockOf(BuildContext context) =>
      usesDock(MediaQuery.sizeOf(context).width);

  /// Height of the tab bar strip (bar, gap and the system inset below it).
  static double dockHeight(double width, double bottomInset) =>
      usesDock(width) ? tabBarHeight + tabBarGap + bottomInset : 0;

  /// What the sliding player panel collapses to: the dock on phones, plus
  /// the mini player once a song is loaded.
  static double panelMinHeight({
    required double width,
    required double bottomInset,
    required bool hasSong,
  }) {
    if (usesDock(width)) {
      return dockHeight(width, bottomInset) +
          (hasSong ? miniPlayerHeight : 0);
    }
    if (!hasSong) return 0;
    return (width > 800 ? 105.0 : miniPlayerHeight) + bottomInset;
  }
}

/// One tab of the floating bar.
class RiffTab {
  const RiffTab({
    required this.key,
    required this.labelKey,
    required this.icon,
    required this.iconOutlined,
    required this.tabIndices,
  });
  final String key;
  final String labelKey;
  final IconData icon;
  final IconData iconOutlined;

  /// Home-screen tab indices this tab stands for (Library covers Songs,
  /// Playlists, Albums and Artists).
  final List<int> tabIndices;
}

const riffTabs = [
  RiffTab(
      key: 'home',
      labelKey: 'home',
      icon: Icons.home_rounded,
      iconOutlined: Icons.home_outlined,
      tabIndices: [0]),
  RiffTab(
      key: 'library',
      labelKey: 'library',
      icon: Icons.library_music_rounded,
      iconOutlined: Icons.library_music_outlined,
      tabIndices: [1, 4, 5, 6]),
  RiffTab(
      key: 'podcasts',
      labelKey: 'podcasts',
      icon: Icons.podcasts_rounded,
      iconOutlined: Icons.podcasts_outlined,
      tabIndices: [2]),
  RiffTab(
      key: 'audiobooks',
      labelKey: 'audiobooks',
      icon: Icons.headphones_rounded,
      iconOutlined: Icons.headphones_outlined,
      tabIndices: [3]),
];

/// Which tab key is lit for a Home tab index and the nested route on top.
String? selectedRiffTab(int tabIndex, String? nestedRoute) {
  if (nestedRoute == ScreenNavigationSetup.searchScreen ||
      nestedRoute == ScreenNavigationSetup.searchResultScreen) {
    return 'search';
  }
  for (final t in riffTabs) {
    if (t.tabIndices.contains(tabIndex)) return t.key;
  }
  return null;
}

/// Bottom of the phone shell: the mini player pill (when a song is loaded)
/// over the floating tab bar. Fades and hides with the player panel the
/// way the mini player used to on its own.
class RiffBottomDock extends StatelessWidget {
  const RiffBottomDock({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Obx(() {
      final total = player.playerPanelMinHeight.value;
      final hasSong =
          total > RiffShell.dockHeight(width, inset) + 1 && !player.initFlagForPlayer;
      return Visibility(
        visible: player.isPlayerpanelTopVisible.value,
        child: AnimatedOpacity(
          opacity: player.playerPaneOpacity.value,
          duration: Duration.zero,
          child: ColoredBox(
            color: theme.canvasColor,
            child: SizedBox(
              height: total,
              width: width,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasSong)
                    SizedBox(
                      height: RiffShell.miniPlayerHeight,
                      child: InkWell(
                        onTap: player.playerPanelController.open,
                        child: const MiniPlayer(docked: true),
                      ),
                    ),
                  const RiffTabBar(),
                  SizedBox(height: RiffShell.tabBarGap + inset),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Echo Music's floating tab bar (iOS 26 style): a centred pill with the
/// main tabs and a round search button beside it.
class RiffTabBar extends StatelessWidget {
  const RiffTabBar({super.key});

  static void select(RiffTab tab) {
    final home = Get.find<HomeScreenController>();
    final nav = Get.nestedKey(ScreenNavigationSetup.id)?.currentState;
    if (nav != null && nav.canPop()) nav.popUntil((r) => r.isFirst);
    if (tab.tabIndices.contains(home.tabIndex.value)) return;
    home.onSideBarTabSelected(tab.tabIndices.first);
  }

  static void openSearch() {
    final home = Get.find<HomeScreenController>();
    if (home.nestedRoute.value == ScreenNavigationSetup.searchScreen) return;
    Get.toNamed(ScreenNavigationSetup.searchScreen,
        id: ScreenNavigationSetup.id);
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    final theme = Theme.of(context);
    final surface = theme.brightness == Brightness.dark
        ? Color.alphaBlend(Colors.white.withOpacity(0.08), theme.cardColor)
        : theme.cardColor;
    final shadow = Colors.black.withOpacity(0.45);
    final border =
        BorderSide(color: theme.dividerColor.withOpacity(0.7), width: 0.5);
    return SizedBox(
      height: RiffShell.tabBarHeight,
      child: Obx(() {
        final selected =
            selectedRiffTab(home.tabIndex.value, home.nestedRoute.value);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Material(
              color: surface,
              elevation: 10,
              shadowColor: shadow,
              shape: StadiumBorder(side: border),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tab in riffTabs)
                      _TabButton(
                        tab: tab,
                        selected: selected == tab.key,
                        onTap: () => RiffTabBar.select(tab),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: surface,
              elevation: 10,
              shadowColor: shadow,
              shape: CircleBorder(side: border),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: RiffTabBar.openSearch,
                child: SizedBox.square(
                  dimension: RiffShell.tabBarHeight,
                  child: Icon(
                    Icons.search_rounded,
                    size: 26,
                    color: selected == 'search'
                        ? theme.colorScheme.secondary
                        : theme.textTheme.titleMedium?.color,
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton(
      {required this.tab, required this.selected, required this.onTap});
  final RiffTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final muted = theme.textTheme.titleSmall?.color ??
        theme.textTheme.titleMedium?.color;
    final color = selected ? accent : muted;
    return InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? tab.icon : tab.iconOutlined, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              tab.labelKey.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
