import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:sidebar_with_animation/animated_side_bar.dart';

import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';

/// Width of the phone rail, measured from the items as they were (4dp +
/// 8dp icon padding + 22dp icon + 8dp + 4dp, plus the selected item's
/// 0.5dp border each side) and now fixed, so expanding Songs (whose
/// sub-items used to be wider) can't shift the content pane. Home sizes
/// its content from the pane that is left.
const double kRailWidth = 47;

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
      iconOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobileOrTabScreen = size.width < 480;
    final homeScreenController = Get.find<HomeScreenController>();
    final theme = Theme.of(context);
    final rail = Align(
      alignment: Alignment.topCenter,
      child: isMobileOrTabScreen
          ? SizedBox(
              width: kRailWidth,
              child: SingleChildScrollView(
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
                        trailing: Semantics(
                          button: true,
                          expanded: _songsExpanded,
                          label: 'songs'.tr,
                          excludeSemantics: true,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _songsExpanded = !_songsExpanded);
                            },
                            // Full rail width, 48dp tall: a real touch target
                            // for a 20dp caret.
                            child: SizedBox(
                              width: kRailWidth,
                              height: 48,
                              child: Center(
                                child: AnimatedRotation(
                                  turns: _songsExpanded ? -0.5 : 0.0,
                                  duration: RiffDurations.select,
                                  curve: RiffDurations.selectCurve,
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: RiffComponentSizes.trailingIcon,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Smoothly expand/collapse the sub-section (size + fade).
                      AnimatedSize(
                        duration: RiffDurations.select,
                        curve: RiffDurations.selectCurve,
                        alignment: Alignment.topCenter,
                        child: AnimatedOpacity(
                          opacity: _songsExpanded ? 1.0 : 0.0,
                          duration: RiffDurations.select,
                          curve: RiffDurations.selectCurve,
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
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(bottom: 100.0),
              child: SideBarAnimated(
                onTap: homeScreenController.onSideBarTabSelected,
                // Lights out: black bar, flat surface2 press feedback. The
                // package draws the active glyph white on its floating
                // indicator, so the indicator keeps the accent (see
                // docs/redesign/SKIPPED.md).
                sideBarColor: theme.colorScheme.surface,
                animatedContainerColor: theme.colorScheme.secondary,
                selectedIconColor: theme.colorScheme.onSurface,
                unselectedIconColor: theme.colorScheme.onSurface,
                unSelectedTextColor: theme.colorScheme.onSurfaceVariant,
                dividerColor: theme.dividerColor,
                textStyle: theme.textTheme.labelLarge!,
                hoverColor: theme.hoverColor,
                splashColor: theme.highlightColor,
                highlightColor: theme.highlightColor,
                widthSwitch: 800,
                mainLogoImage: 'assets/icons/icon.png',
                sidebarItems: [
                  for (final d in _destinations)
                    SideBarItem(
                      iconSelected: d.icon,
                      iconUnselected: d.iconOutlined,
                      // Settings: cog only — no "Settings" label on the rail.
                      text: d.iconOnly ? '' : d.labelKey.tr,
                    ),
                ],
              ),
            ),
    );
    if (!isMobileOrTabScreen) return rail;
    // Right edge: one-physical-pixel hairline, inside the rail's width.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor, width: 0)),
      ),
      child: rail,
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
    final item = _RailItem(
      destination: destination,
      selected: isSelected,
      sub: sub,
      onTap: () => controller.onSideBarTabSelected(destination.index),
    );
    // TalkBack reads the destination once, as a selectable button.
    final labelled = Semantics(
      button: true,
      selected: isSelected,
      label: destination.labelKey.tr,
      excludeSemantics: true,
      child: item,
    );
    final entry = destination.iconOnly
        ? Tooltip(message: destination.labelKey.tr, child: labelled)
        : labelled;
    if (trailing == null) return entry;
    return Column(mainAxisSize: MainAxisSize.min, children: [entry, trailing]);
  }
}

/// Lights-out rail entry: outline glyph in the primary text colour, filled
/// accent glyph when active, no pill behind it. Pressing shows a flat
/// circular highlight behind the glyph; a tap gives a selection click.
class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.sub,
    required this.onTap,
  });

  final _RailDestination destination;
  final bool selected;
  final bool sub;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rail = theme.navigationRailTheme;
    final accent = theme.colorScheme.secondary;
    final d = widget.destination;
    final sub = widget.sub;
    final selected = widget.selected;
    final iconColor = selected ? accent : theme.colorScheme.onSurface;
    final labelStyle = selected
        ? rail.selectedLabelTextStyle?.copyWith(color: accent)
        : rail.unselectedLabelTextStyle;
    return InkWell(
      // The circle below is the press feedback; no rectangle highlight.
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      onHighlightChanged: (v) => setState(() => _pressed = v),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: sub ? RiffSpacing.xs : RiffSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: RiffDurations.press,
              width: RiffComponentSizes.railHighlight,
              height: RiffComponentSizes.railHighlight,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pressed ? theme.highlightColor : Colors.transparent,
              ),
              child: Icon(
                selected ? d.icon : d.iconOutlined,
                size: sub
                    ? RiffComponentSizes.railSubIcon
                    : RiffComponentSizes.railIcon,
                color: iconColor,
              ),
            ),
            if (!d.iconOnly) ...[
              const SizedBox(height: RiffSpacing.xs),
              RotatedBox(
                quarterTurns: -1,
                child: AnimatedDefaultTextStyle(
                  duration: RiffDurations.select,
                  curve: RiffDurations.selectCurve,
                  style: labelStyle ?? DefaultTextStyle.of(context).style,
                  child: Text(d.labelKey.tr),
                ),
              ),
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
    this.iconOnly = false,
  });

  final int index;
  final String labelKey;
  final IconData icon;
  final IconData iconOutlined;

  /// When true, render only the glyph (no rail label text).
  final bool iconOnly;
}
