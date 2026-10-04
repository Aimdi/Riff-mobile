import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../Search/components/desktop_search_bar.dart';
import '/ui/screens/Search/search_screen_controller.dart';
import '/ui/widgets/animated_screen_transition.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Podcasts/podcasts_library.dart';
import '../Audiobooks/audiobooks_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../widgets/discovery/riff_wave_hero.dart';
import '../../utils/riff_tokens.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import '/services/spotify_home.dart';
import 'home_feed_builder.dart';
import 'home_feed_data.dart';
import 'home_greeting.dart';
import 'home_hero_carousel.dart';
import 'home_jump_back_in.dart';
import 'home_layout.dart';
import 'home_metrics.dart';
import 'home_screen_controller.dart';
import 'home_sections.dart';
import 'home_shelves.dart';
import 'home_speed_dial.dart';
import 'home_stats_card.dart';
import 'home_station_chips.dart';
import '../Settings/settings_screen.dart';
import '/ui/widgets/riff_header_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        // Search lives in the Home title row; keep FAB only for Library add.
        floatingActionButton: Obx(
          () => homeScreenController.tabIndex.value == 4
              ? Obx(
                  () => Padding(
                    padding: EdgeInsets.only(
                        bottom: playerController.playerPanelMinHeight.value >
                                Get.mediaQuery.padding.bottom
                            ? playerController.playerPanelMinHeight.value -
                                Get.mediaQuery.padding.bottom
                            : playerController.playerPanelMinHeight.value),
                    child: SizedBox(
                      height: 60,
                      width: 60,
                      child: FittedBox(
                        child: FloatingActionButton(
                            focusElevation: 0,
                            shape: const RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(14))),
                            elevation: 0,
                            onPressed: () async {
                              showDialog(
                                  context: context,
                                  builder: (context) =>
                                      const CreateNRenamePlaylistPopup());
                            },
                            child: const Icon(Icons.add)),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // Outer Obx removed: after bottom-nav removal it no longer read any
        // observables (SideNavBar is always shown). Empty Obx throws in GetX
        // and blanks SideNavBar + Body while the FAB Obx still paints.
        body: Row(
          children: <Widget>[
            const SideNavBar(),
            Expanded(
              child: Obx(() => AnimatedScreenTransition(
                  enabled: settingsScreenController
                      .isTransitionAnimationDisabled.isFalse,
                  resverse: homeScreenController.reverseAnimationtransiton,
                  horizontalTransition: false,
                  child: Center(
                    key: ValueKey<int>(homeScreenController.tabIndex.value),
                    child: const Body(),
                  ))),
            ),
          ],
        ));
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final homeScreenController = Get.find<HomeScreenController>();
    final size = MediaQuery.of(context).size;
    final topPadding = GetPlatform.isDesktop
        ? 85.0
        : context.isLandscape
            ? 50.0
            : size.height < 750
                ? 80.0
                : 85.0;
    const leftPadding = 0.0;
    if (homeScreenController.tabIndex.value == 0) {
      return Padding(
        padding: const EdgeInsets.only(left: leftPadding),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () {
                // for Desktop search bar
                if (GetPlatform.isDesktop) {
                  final sscontroller = Get.find<SearchScreenController>();
                  if (sscontroller.focusNode.hasFocus) {
                    sscontroller.focusNode.unfocus();
                  }
                }
              },
              child: Obx(
                () => homeScreenController.networkError.isTrue
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height - 180,
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Text(
                                  "home".tr,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "networkError1".tr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 15, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .textTheme
                                            .titleLarge!
                                            .color,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          homeScreenController
                                              .loadContentFromNetwork();
                                        },
                                        child: Text(
                                          "retry".tr,
                                          style: TextStyle(
                                            color:
                                                Theme.of(context).canvasColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _HomeFeed(topPadding: topPadding),
              ),
            ),
            if (GetPlatform.isDesktop)
              Align(
                alignment: Alignment.topCenter,
                child: LayoutBuilder(builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth > 800
                        ? 800
                        : constraints.maxWidth - 40,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 15.0),
                      child: DesktopSearchBar(),
                    ),
                  );
                }),
              ),
          ],
        ),
      );
    } else if (homeScreenController.tabIndex.value == 1) {
      return const SongsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 2) {
      return const PodcastsLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 3) {
      return const AudiobooksScreen();
    } else if (homeScreenController.tabIndex.value == 4) {
      return const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (homeScreenController.tabIndex.value == 5) {
      return const PlaylistNAlbumLibraryWidget();
    } else if (homeScreenController.tabIndex.value == 6) {
      return const LibraryArtistWidget();
    } else if (homeScreenController.tabIndex.value == 7) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("${homeScreenController.tabIndex.value}"),
      );
    }
  }
}

/// The Home tab: a fixed order of sections from [buildHomeSections],
/// sized from the pane right of the rail. Edge to edge: only the header
/// gets the status-bar inset, and a gradient keeps text from showing
/// behind the status-bar icons as the feed scrolls under it.
class _HomeFeed extends StatefulWidget {
  const _HomeFeed({required this.topPadding});

  /// Desktop: room for the search bar above the header.
  final double topPadding;

  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  /// Recently played, read when Home opens or refreshes — not on every
  /// play, so Speed dial doesn't reshuffle under the user's finger.
  List<MediaItem> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    // Cached Spotify shelves show at once; stale ones refresh behind them.
    SpotifyHome.refresh();
  }

  Future<void> _loadRecent() async {
    if (!Hive.isBoxOpen('LIBRP')) {
      try {
        await Hive.openBox('LIBRP');
      } catch (_) {}
    }
    if (mounted) setState(() => _recent = recentSongs());
  }

  Future<void> _refresh() async {
    await _loadRecent();
    await Future.wait([
      Get.find<HomeScreenController>().loadContentFromNetwork(silent: true),
      SpotifyHome.refresh(force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final statusTop = MediaQuery.paddingOf(context).top;
    final headerTop = GetPlatform.isDesktop ? widget.topPadding : statusTop + 8;
    final bg = theme.scaffoldBackgroundColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            theme.colorScheme.onSurface.withOpacity(0.002),
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            dark ? Brightness.light : Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final metrics = HomeMetrics(constraints.maxWidth);
        return Stack(
          children: [
            Obx(() {
              final bottom = homeBottomPadding(context);
              if (home.isContentFetched.isFalse) {
                return ListView(
                  padding: EdgeInsets.only(bottom: bottom),
                  children: [
                    _HomeHeader(top: headerTop),
                    const HomeShimmer(),
                  ],
                );
              }
              HomeSectionPrefs.ensureLoaded();
              final hidden = HomeSectionPrefs.hidden.toSet();
              final sections = buildHomeSections(
                  readHomeFeedInput(recent: _recent, hidden: hidden));
              // The Spotify session ended: one card where its shelves go.
              final reconnect = SpotifyHome.needsReconnect.value &&
                  !hidden.contains(HomeSection.spotify);
              final reconnectAt = reconnect
                  ? sections.indexWhere(
                      (m) => m.section.index > HomeSection.spotify.index)
                  : -1;
              return RefreshIndicator(
                edgeOffset: headerTop,
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.only(bottom: bottom),
                  children: [
                    for (var i = 0; i < sections.length; i++) ...[
                      if (i == reconnectAt) const _SpotifyReconnectCard(),
                      ..._sectionWidgets(home, sections[i], metrics, headerTop),
                    ],
                    if (reconnect && reconnectAt < 0)
                      const _SpotifyReconnectCard(),
                  ],
                ),
              );
            }),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusTop + 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [bg, bg.withOpacity(0)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  List<Widget> _sectionWidgets(HomeScreenController home, HomeSectionModel m,
      HomeMetrics metrics, double headerTop) {
    Widget slot(Widget child, [Key? key]) => HomeSectionSlot(
        key: key ?? ValueKey(m.section), section: m.section, child: child);
    switch (m.section) {
      case HomeSection.header:
        return [
          _HomeHeader(key: const ValueKey('header'), top: headerTop),
          Obx(() => home.showingCachedWhileOffline.isTrue
              ? const _OfflineHomeBanner()
              : const SizedBox.shrink()),
        ];
      case HomeSection.jumpBackIn:
        return [slot(HomeJumpBackIn(items: m.items, metrics: metrics))];
      case HomeSection.riffWave:
        return [
          slot(const Column(
            mainAxisSize: MainAxisSize.min,
            children: [RiffWaveHero(), RiffStationChips()],
          )),
        ];
      case HomeSection.speedDial:
        return [slot(HomeSpeedDial(items: m.items, metrics: metrics))];
      case HomeSection.quickPicks:
        return [
          slot(HomeHeroCarousel(
            songs: [
              for (final i in m.items)
                if (i.value is MediaItem) i.value as MediaItem
            ],
            metrics: metrics,
          )),
        ];
      case HomeSection.personalized:
      case HomeSection.spotify:
      case HomeSection.editorial:
        return [
          for (final shelf in m.shelves)
            slot(
              RiffShelf(
                shelf: shelf,
                metrics: metrics,
                controller: home.scrollControllerFor('shelf_${shelf.id}'),
              ),
              ValueKey('${m.section.name}_${shelf.id}'),
            ),
        ];
      case HomeSection.yourWeek:
        return [slot(const HomeStatsCard())];
      case HomeSection.exploreMore:
        return [const _ExploreMoreButton(key: ValueKey('exploreMore'))];
    }
  }
}

/// Greeting on the left (one line), Explore, Stats and Search on the
/// right. Only this row clears the status bar.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({super.key, required this.top});
  final double top;

  void _go(String route) => Get.toNamed(route, id: ScreenNavigationSetup.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls with the feed, so no hairline; header icon size and colour.
    return RiffHeaderBar(
        child: Padding(
      padding: EdgeInsets.only(
          left: RiffSpacing.gutter, top: top, right: RiffSpacing.xs),
      child: SizedBox(
        height: RiffSpacing.headerRow,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                // One line: shrinks to fit on small phones and with large
                // system text rather than cutting the greeting.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    homeGreetingKey(DateTime.now()).tr,
                    maxLines: 1,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'explore'.tr,
              icon: const Icon(Icons.explore_outlined),
              onPressed: () => _go(ScreenNavigationSetup.exploreScreen),
            ),
            IconButton(
              tooltip: 'stats'.tr,
              icon: const Icon(Icons.bar_chart_rounded),
              onPressed: () => _go(ScreenNavigationSetup.statsScreen),
            ),
            if (!GetPlatform.isDesktop)
              IconButton(
                tooltip: 'search'.tr,
                icon: const Icon(Icons.search_rounded),
                onPressed: () => _go(ScreenNavigationSetup.searchScreen),
              ),
          ],
        ),
      ),
    ));
  }
}

/// The Spotify session ended (or its six-month sign-in ran out): sign in
/// again from the Spotify screen.
class _SpotifyReconnectCard extends StatelessWidget {
  const _SpotifyReconnectCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.gutter,
          top: RiffSpacing.section,
          right: RiffSpacing.gutter),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(RiffSizes.shelfRadius),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          minVerticalPadding: 12,
          leading: const Icon(Icons.link_off_rounded),
          title: Text('spotifyHomeReconnect'.tr),
          subtitle: Text('spotifyHomeReconnectDes'.tr),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Get.toNamed(ScreenNavigationSetup.spotifyBridgeScreen,
              id: ScreenNavigationSetup.id),
        ),
      ),
    );
  }
}

/// Last thing on Home: the rest of the YouTube Music feed.
class _ExploreMoreButton extends StatelessWidget {
  const _ExploreMoreButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.gutter,
          top: RiffSpacing.section,
          right: RiffSpacing.gutter),
      child: SizedBox(
        width: double.infinity,
        height: RiffSizes.touch,
        child: FilledButton.tonalIcon(
          onPressed: () => Get.toNamed(ScreenNavigationSetup.exploreScreen,
              id: ScreenNavigationSetup.id),
          icon: const Icon(Icons.explore_outlined),
          label: Text('exploreMore'.tr),
        ),
      ),
    );
  }
}

/// Soft strip when Home is showing cached shelves after a silent network miss.
class _OfflineHomeBanner extends StatelessWidget {
  const _OfflineHomeBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.gutter,
          top: RiffSpacing.sm,
          right: RiffSpacing.gutter),
      child: Material(
        color: homeTileColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
          side: homeTileBorder(context),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
          onTap: () =>
              Get.find<HomeScreenController>().loadContentFromNetwork(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'offlineHomeBanner'.tr,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  'retry'.tr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
