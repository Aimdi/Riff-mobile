import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:sidebar_with_animation/animated_side_bar.dart';

// Tab indices used by HomeScreenController.onSideBarTabSelected:
// 0 Home, 1 Songs, 2 Podcasts, 3 Audiobooks, 4 Playlists, 5 Albums,
// 6 Artists, 7 Settings.
class SideNavBar extends StatefulWidget {
  const SideNavBar({super.key});

  @override
  State<SideNavBar> createState() => _SideNavBarState();
}

class _SideNavBarState extends State<SideNavBar> {
  // Songs accordion: Playlists / Albums / Artists live under Songs now.
  bool _songsExpanded = false;

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
                    _railItem(homeScreenController, sel, index: 0, label: "home".tr),
                    // Songs — tap opens Songs, the caret expands the sub-section.
                    _railItem(
                      homeScreenController,
                      sel,
                      index: 1,
                      label: "songs".tr,
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
                              Icons.keyboard_arrow_down,
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
                                  _railItem(homeScreenController, sel,
                                      index: 4,
                                      label: "playlists".tr,
                                      sub: true),
                                  _railItem(homeScreenController, sel,
                                      index: 5, label: "albums".tr, sub: true),
                                  _railItem(homeScreenController, sel,
                                      index: 6, label: "artists".tr, sub: true),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ),
                    _railItem(homeScreenController, sel,
                        index: 2, label: "podcasts".tr),
                    _railItem(homeScreenController, sel,
                        index: 3, label: "audiobooks".tr),
                    _railItem(homeScreenController, sel,
                        index: 7, label: "settings".tr),
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
                  SideBarItem(
                    iconSelected: Icons.home,
                    iconUnselected: Icons.home_outlined,
                    text: 'home'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.audiotrack,
                    iconUnselected: Icons.audiotrack,
                    text: 'songs'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.podcasts,
                    iconUnselected: Icons.podcasts,
                    text: 'podcasts'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.menu_book,
                    iconUnselected: Icons.menu_book,
                    text: 'audiobooks'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.library_music,
                    iconUnselected: Icons.library_music_outlined,
                    text: 'playlists'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.album,
                    iconUnselected: Icons.album_outlined,
                    text: 'albums'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.person,
                    text: 'artists'.tr,
                  ),
                  SideBarItem(
                    iconSelected: Icons.settings,
                    iconUnselected: Icons.settings_outlined,
                    text: 'settings'.tr,
                  ),
                ],
              ),
            ),
    );
  }

  /// One vertical (rotated-label) rail entry. [sub] renders the smaller,
  /// indented accordion children. [selectedForIndices] lets the Songs parent
  /// stay highlighted while a child tab (Playlists/Albums/Artists) is active.
  Widget _railItem(
    HomeScreenController controller,
    int selected, {
    required int index,
    required String label,
    bool sub = false,
    List<int>? selectedForIndices,
    Widget? trailing,
  }) {
    final isSelected =
        selectedForIndices?.contains(selected) ?? (selected == index);
    final accent = Theme.of(context).colorScheme.secondary;
    final normal = Theme.of(context).textTheme.titleLarge!.color;
    final color = isSelected ? accent : normal;
    return InkWell(
      onTap: () => controller.onSideBarTabSelected(index),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: sub ? 6 : 10, horizontal: sub ? 14 : 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
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
