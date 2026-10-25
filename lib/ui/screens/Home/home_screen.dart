import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/theme/riff_tokens.dart' show RiffDurations, RiffMotionDistances;
import '/ui/widgets/animated_screen_transition.dart';
import '/ui/widgets/rows_reveal.dart';
import '/ui/widgets/shimmer_widgets/reveal.dart';
import '../../widgets/side_nav_bar.dart';
import '../Library/library.dart';
import '../Podcasts/podcast_empty_state.dart';
import '../Podcasts/podcasts_library.dart';
import '../Audiobooks/audiobooks_screen.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/create_playlist_dialog.dart';
import '../../navigator.dart';
import '../../utils/riff_tokens.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import '/services/spotify_home.dart';
import 'discover_screen.dart';
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
import '../Settings/settings_screen.dart';
import '/ui/widgets/riff_header_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// The Playlists add button growing in, as a toggle does (a like).
  static final Animatable<double> _fabGrow =
      Tween<double>(begin: RiffMotionDistances.popFromScale, end: 1)
          .chain(CurveTween(curve: RiffDurations.popCurve));

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    final HomeScreenController homeScreenController =
        Get.find<HomeScreenController>();
    final SettingsScreenController settingsScreenController =
        Get.find<SettingsScreenController>();

    return Scaffold(
        // Search lives in the Discover tab; keep FAB only for Library add.
        floatingActionButton: Obx(() {
          final show = homeScreenController.tabIndex.value == RailTab.playlists;
          final panel = playerController.playerPanelMinHeight.value;
          final safeBottom = Get.mediaQuery.padding.bottom;
          final lift = panel > safeBottom ? panel - safeBottom : panel;
          const size = 60.0;
          // It grows and fades in (and out, as Playlists is left) about its
          // own centre, not the mini-player lift under it.
          final centre = Alignment(0, -lift / (size + lift));
          return AnimatedSwitcher(
            duration: RiffDurations.select,
            switchInCurve: RiffDurations.enterCurve,
            switchOutCurve: RiffDurations.exitCurve,
            // The button fading out (Playlists left) takes no more taps;
            // the same wrapper for both, so neither is rebuilt.
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: [
                for (final child in previous)
                  IgnorePointer(key: child.key, child: child),
                if (current != null)
                  IgnorePointer(
                      key: current.key, ignoring: false, child: current),
              ],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                alignment: centre,
                scale: _fabGrow.animate(animation),
                child: child,
              ),
            ),
            child: show
                ? Padding(
                    key: const ValueKey('addPlaylist'),
                    padding: EdgeInsets.only(bottom: lift),
                    child: SizedBox(
                      height: size,
                      width: size,
                      child: FittedBox(
                        child: FloatingActionButton(
                            tooltip: 'CreateNewPlaylist'.tr,
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
                  )
                : const SizedBox.shrink(),
          );
        }),
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
                  forward: homeScreenController.reverseAnimationtransiton,
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
    const leftPadding = 0.0;
    final tab = homeScreenController.tabIndex.value;
    if (tab == RailTab.home) {
      return Padding(
        padding: const EdgeInsets.only(left: leftPadding),
        child: Stack(
          children: [
            Obx(
              () => homeScreenController.networkError.isTrue
                  // Offline: the page title where every tab has it, and
                  // the app's empty state with Retry.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                              left: HomeLayout.gutter,
                              top: riffTabTop(context),
                              right: HomeLayout.gutter),
                          child: SizedBox(
                            height: RiffSpacing.headerRow,
                            child: RiffPageTitle('home'.tr),
                          ),
                        ),
                        Expanded(
                          child: PodcastEmptyState(
                            icon: Icons.wifi_off_rounded,
                            message: 'networkError1'.tr,
                            actionLabel: 'retry'.tr,
                            actionIcon: Icons.refresh_rounded,
                            onAction:
                                homeScreenController.loadContentFromNetwork,
                          ),
                        ),
                      ],
                    )
                  : const _HomeFeed(),
            ),
          ],
        ),
      );
    } else if (tab == RailTab.discover) {
      return const DiscoverScreen();
    } else if (tab == RailTab.songs) {
      return const SongsLibraryWidget();
    } else if (tab == RailTab.podcasts) {
      return const PodcastsLibraryWidget();
    } else if (tab == RailTab.audiobooks) {
      return const AudiobooksScreen();
    } else if (tab == RailTab.playlists) {
      return const PlaylistNAlbumLibraryWidget(isAlbumContent: false);
    } else if (tab == RailTab.albums) {
      return const PlaylistNAlbumLibraryWidget();
    } else if (tab == RailTab.artists) {
      return const LibraryArtistWidget();
    } else if (tab == RailTab.settings) {
      return const SettingsScreen();
    } else {
      return Center(
        child: Text("$tab"),
      );
    }
  }
}

/// The Home tab: a fixed order of sections from [buildHomeSections],
/// sized from the pane right of the rail. Edge to edge: only the header
/// gets the status-bar inset, and a gradient keeps text from showing
/// behind the status-bar icons as the feed scrolls under it.
class _HomeFeed extends StatefulWidget {
  const _HomeFeed();

  @override
  State<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed>
    with SingleTickerProviderStateMixin {
  /// Recently played, read when Home opens or refreshes — not on every
  /// play, so Speed dial doesn't reshuffle under the user's finger.
  List<MediaItem> _recent = const [];

  /// The sections replacing the loading skeleton fade in together.
  // Made in initState: made lazily, a screen closed before its content
  // came would create it in dispose.
  late final RowsReveal _reveal;
  bool _skeleton = false;

  @override
  void initState() {
    super.initState();
    _reveal = RowsReveal(vsync: this);
    _loadRecent();
    // Cached Spotify shelves show at once; stale ones refresh behind them.
    SpotifyHome.refresh();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
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
    HapticFeedback.mediumImpact();
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
    final headerTop = statusTop + 8;
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
                _skeleton = true;
                return ListView(
                  padding: EdgeInsets.only(bottom: bottom),
                  children: [
                    _HomeHeader(top: headerTop),
                    const HomeShimmer(),
                  ],
                );
              }
              if (_skeleton) {
                _skeleton = false;
                _reveal.play();
              }
              HomeSectionPrefs.ensureLoaded();
              final hidden = HomeSectionPrefs.hidden.toSet();
              final sections = buildHomeSections(
                  readHomeFeedInput(recent: _recent, hidden: hidden));
              // The Spotify session ended: one card where its shelves go.
              // Its place stays (empty otherwise) so it opens and folds
              // away there instead of popping in.
              final reconnect = SpotifyHome.needsReconnect.value &&
                  !hidden.contains(HomeSection.spotify);
              final reconnectAt = sections.indexWhere(
                  (m) => m.section.index > HomeSection.spotify.index);
              final reconnectCard = RiffReveal(
                  key: const ValueKey('spotifyReconnect'),
                  child: reconnect ? const _SpotifyReconnectCard() : null);
              final rows = [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i == reconnectAt) reconnectCard,
                  ..._sectionWidgets(home, sections[i], metrics, headerTop),
                ],
                if (reconnectAt < 0) reconnectCard,
              ];
              return RefreshIndicator(
                edgeOffset: headerTop,
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.only(bottom: bottom),
                  children: [
                    // The header was there with the skeleton: it stays put.
                    for (final row in rows)
                      row is _HomeHeader ? row : _reveal.row(row, key: row.key),
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

  /// Sections follow each other on space alone, no rules between them,
  /// as Spotify, YouTube Music and Apple Music lay out their feeds.
  List<Widget> _sectionWidgets(HomeScreenController home, HomeSectionModel m,
      HomeMetrics metrics, double headerTop) {
    Widget slot(Widget child, [Key? key]) => HomeSectionSlot(
        key: key ?? ValueKey(m.section), section: m.section, child: child);
    switch (m.section) {
      case HomeSection.header:
        return [
          _HomeHeader(key: const ValueKey('header'), top: headerTop),
          // Opens and folds away rather than popping in and out.
          Obx(() => RiffReveal(
              child: home.showingCachedWhileOffline.isTrue
                  ? const _OfflineHomeBanner()
                  : null)),
        ];
      case HomeSection.jumpBackIn:
        return [slot(HomeJumpBackIn(items: m.items, metrics: metrics))];
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
          for (final (i, shelf) in m.shelves.indexed)
            slot(
              RiffShelf(
                // "Spotify" over the first of its shelves, not every one.
                shelf: m.section == HomeSection.spotify && i > 0
                    ? shelf.withoutKicker()
                    : shelf,
                metrics: metrics,
                controller: home.scrollControllerFor('shelf_${shelf.id}'),
              ),
              ValueKey('${m.section.name}_${shelf.id}'),
            ),
        ];
      case HomeSection.yourWeek:
        return [slot(const HomeStatsCard())];
      case HomeSection.exploreMore:
        return [
          slot(const _ExploreMoreButton(), const ValueKey('exploreMore'))
        ];
    }
  }
}

/// Greeting on the left (one line), Stats (and "What's playing?" on
/// Android) on the right; search and Explore live in the Discover tab.
/// Only this row clears the status bar.
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
              tooltip: 'stats'.tr,
              icon: const Icon(Icons.bar_chart_rounded),
              onPressed: () => _go(ScreenNavigationSetup.statsScreen),
            ),
            // "What's playing?" — listen and name the song (Android).
            if (GetPlatform.isAndroid)
              IconButton(
                tooltip: 'whatsPlaying'.tr,
                icon: const Icon(Icons.mic_none_rounded),
                onPressed: () => _go(ScreenNavigationSetup.recognizeScreen),
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
  const _ExploreMoreButton();

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
