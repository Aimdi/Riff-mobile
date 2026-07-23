import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sidebar_with_animation/animated_side_bar.dart';

import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';

// Tab indices used by HomeScreenController.onSideBarTabSelected:
// 0 Home, 1 Songs, 2 Podcasts, 3 Audiobooks, 4 Playlists,
// 5 Albums, 6 Artists, 7 Settings.
// Cloud lives under Songs (toolbar toggle), not on the rail.
class SideNavBar extends StatefulWidget {
  const SideNavBar({super.key});

  @override
  State<SideNavBar> createState() => _SideNavBarState();
}

class _SideNavBarState extends State<SideNavBar> {
  // Songs accordion: Playlists / Albums / Artists live under Songs now.
  bool _songsExpanded = false;

  static const _destinations = <_RailDestination>[
    _RailDestination(
      index: 0,
      labelKey: 'home',
      icon: Icons.home_rounded,
      iconOutlined: Icons.home_outlined,
    ),
    _RailDestination(
      index: 1,
      labelKey: 'songs',
      icon: Icons.music_note_rounded,
      iconOutlined: Icons.music_note_outlined,
    ),
    _RailDestination(
      index: 2,
      labelKey: 'podcasts',
      icon: Icons.podcasts_rounded,
      iconOutlined: Icons.podcasts_outlined,
    ),
    _RailDestination(
      index: 3,
      labelKey: 'audiobooks',
      icon: Icons.headphones_rounded,
      iconOutlined: Icons.headphones_outlined,
    ),
    _RailDestination(
      index: 4,
      labelKey: 'playlists',
      icon: Icons.queue_music_rounded,
      iconOutlined: Icons.queue_music,
    ),
    _RailDestination(
      index: 5,
      labelKey: 'albums',
      icon: Icons.album_rounded,
      iconOutlined: Icons.album_outlined,
    ),
    _RailDestination(
      index: 6,
      labelKey: 'artists',
      icon: Icons.mic_rounded,
      iconOutlined: Icons.mic_none_rounded,
    ),
    _RailDestination(
      index: 7,
      labelKey: 'settings',
      icon: Icons.settings_rounded,
      iconOutlined: Icons.settings_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobileOrTabScreen = size.width < 480;
    final homeScreenController = Get.find<HomeScreenController>();
    return Align(
      alignment: Alignment.topCenter,
      child: isMobileOrTabScreen
          ? SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: size.height < 750 ? 30 : 60, bottom: 80),
              child: Obx(() {
                final sel = homeScreenController.tabIndex.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _railItem(
                      homeScreenController,
                      sel,
                      destination: _destinations[0],
                    ),
                    // Songs — tap opens Songs, the caret expands the sub-section.
                    _railItem(
                      homeScreenController,
                      sel,
                      destination: _destinations[1],
                      // sub-items are "selected" too so Songs stays highlighted
                      selectedForIndices: const [1, 4, 5, 6],
                      trailing: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            setState(() => _songsExpanded = !_songsExpanded),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: AnimatedRotation(
                            turns: _songsExpanded ? -0.5 : 0.0,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeInOutCubic,
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color:
                                  Theme.of(context).textTheme.titleLarge!.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Smoothly expand/collapse the sub-section (size + fade).
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedOpacity(
                        opacity: _songsExpanded ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        child: _songsExpanded
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _railItem(
                                    homeScreenController,
                                    sel,
                                    destination: _destinations[4],
                                    sub: true,
                                  ),
                                  _railItem(
                                    homeScreenController,
                                    sel,
                                    destination: _destinations[5],
                                    sub: true,
                                  ),
                                  _railItem(
                                    homeScreenController,
                                    sel,
                                    destination: _destinations[6],
                                    sub: true,
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    _railItem(
                      homeScreenController,
                      sel,
                      destination: _destinations[2],
                    ),
                    _railItem(
                      homeScreenController,
                      sel,
                      destination: _destinations[3],
                    ),
                    _railItem(
                      homeScreenController,
                      sel,
                      destination: _destinations[7],
                    ),
                  ],
                );
              }),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 100.0),
              child: SideBarAnimated(
                onTap: homeScreenController.onSideBarTabSelected,
                sideBarColor: Theme.of(context).primaryColor.withAlpha(250),
                animatedContainerColor: Theme.of(context).colorScheme.secondary,
                hoverColor:
                    Theme.of(context).colorScheme.secondary.withAlpha(180),
                splashColor: Theme.of(context).colorScheme.secondary,
                highlightColor:
                    Theme.of(context).colorScheme.secondary.withAlpha(180),
                widthSwitch: 800,
                mainLogoImage: 'assets/icons/icon.png',
                sidebarItems: [
                  for (final d in _destinations)
                    SideBarItem(
                      iconSelected: d.icon,
                      iconUnselected: d.iconOutlined,
                      text: d.labelKey.tr,
                    ),
                ],
              ),
            ),
    );
  }

  /// One vertical rail entry with a destination glyph + rotated label.
  /// [sub] renders the smaller, indented accordion children.
  /// [selectedForIndices] lets the Songs parent stay highlighted while a
  /// child tab (Playlists/Albums/Artists) is active.
  Widget _railItem(
    HomeScreenController controller,
    int selected, {
    required _RailDestination destination,
    bool sub = false,
    List<int>? selectedForIndices,
    Widget? trailing,
  }) {
    final isSelected = selectedForIndices?.contains(selected) ??
        (selected == destination.index);
    final accent = Theme.of(context).colorScheme.secondary;
    final normal = Theme.of(context).textTheme.titleLarge!.color;
    final color = isSelected ? accent : normal;
    return InkWell(
      onTap: () => controller.onSideBarTabSelected(destination.index),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: sub ? 6 : 10, horizontal: sub ? 14 : 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? destination.icon : destination.iconOutlined,
              size: sub ? 18 : 22,
              color: color,
            ),
            const SizedBox(height: 6),
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                destination.labelKey.tr,
                style: TextStyle(
                  color: color,
                  fontSize: sub ? 13 : 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(height: 4),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

class _RailDestination {
  const _RailDestination({
    required this.index,
    required this.labelKey,
    required this.icon,
    required this.iconOutlined,
  });

  final int index;
  final String labelKey;
  final IconData icon;
  final IconData iconOutlined;
}
