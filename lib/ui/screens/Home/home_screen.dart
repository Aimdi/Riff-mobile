import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
import '../../widgets/discovery/home_discovery_section.dart';
import '../../widgets/discovery/jump_back_in_row.dart';
import '../../widgets/discovery/riff_wave_hero.dart';
import '../../utils/riff_tokens.dart';
import '../../widgets/quickpickswidget.dart';
import '../../widgets/shimmer_widgets/home_shimmer.dart';
import '../../widgets/snackbar.dart';
import '../../../services/discovery/discovery_service.dart';
import '../../../services/discovery/discovery_types.dart';
import '../../../services/podcast_progress_service.dart';
import 'home_explore_section.dart';
import 'home_feed_view_model.dart';
import 'home_greeting.dart';
import 'home_screen_controller.dart';
import 'podcast_continue.dart';
import '../Settings/settings_screen.dart';

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
                                  style:
                                      Theme.of(context).textTheme.titleLarge,
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

/// Home tab feed with narrow Obx scopes so discovery / Quick Picks / shelves
/// don't rebuild each other (and don't churn ScrollControllers).
class _HomeFeed extends StatelessWidget {
  const _HomeFeed({required this.topPadding});
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return Obx(() {
      if (home.isContentFetched.isFalse) {
        return ListView(
          padding: EdgeInsets.only(bottom: 200, top: topPadding),
          children: const [HomeShimmer()],
        );
      }
      return ListView(
        padding: EdgeInsets.only(bottom: 200, top: topPadding),
        children: [
          // Hierarchy: offline → title → continue → Jump back in → Wave → shortcuts.
          Obx(() => home.showingCachedWhileOffline.isTrue
              ? const _OfflineHomeBanner()
              : const SizedBox.shrink()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    homeGreetingKey(DateTime.now()).tr,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          letterSpacing: -0.35,
                        ),
                  ),
                ),
                if (!GetPlatform.isDesktop)
                  IconButton(
                    tooltip: 'search'.tr,
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      Get.toNamed(ScreenNavigationSetup.searchScreen,
                          id: ScreenNavigationSetup.id);
                    },
                  ),
              ],
            ),
          ),
          const _ContinueListeningChip(),
          const _PodcastContinueChip(),
          const JumpBackInRow(),
          const RiffWaveHero(),
          const HomeShortcutGrid(),
          const SizedBox(height: 8),
          const _HomeZoneB(),
          const SizedBox(height: 12),
          const HomeExploreSection(),
        ],
      );
    });
  }
}

/// Zone B — personalised: daily mixes → quick picks → one contextual row.
/// Order, caps, and global dedupe come from [assembleHomeFeedViewModel].
class _HomeZoneB extends StatelessWidget {
  const _HomeZoneB();

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeScreenController>();
    return Obx(() {
      final personal = Get.isRegistered<DiscoveryService>()
          ? Get.find<DiscoveryService>().personalSections.toList()
          : <DiscoverySection>[];
      // Touch mixes-updated pill so Obx rebuilds when it flips.
      if (Get.isRegistered<DiscoveryService>()) {
        final _ = Get.find<DiscoveryService>().mixesUpdatedPill.value;
      }
      final vm = assembleHomeFeedViewModel(
        personalSections: personal,
        quickPicks: home.quickPicks.value,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Get.isRegistered<DiscoveryService>() &&
              Get.find<DiscoveryService>().mixesUpdatedPill.value)
            const _MixesUpdatedBanner(),
          if (vm.dailyMixes != null)
            HomeDiscoverySection(section: vm.dailyMixes!),
          if (vm.quickPicks != null && vm.quickPicks!.songList.isNotEmpty)
            QuickPicksWidget(
              content: vm.quickPicks!,
              scrollController: home.scrollControllerFor('quick_picks'),
            )
          else if (vm.dailyMixes == null &&
              vm.contextual == null &&
              home.quickPicks.value.songList.isEmpty)
            const _HomeDiscoverEmptyCard(),
          if (vm.contextual != null)
            HomeDiscoverySection(section: vm.contextual!),
        ],
      );
    });
  }
}

class _MixesUpdatedBanner extends StatelessWidget {
  const _MixesUpdatedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Text(
        'mixesUpdated'.tr,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.textTheme.titleSmall?.color?.withOpacity(0.55),
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _HomeDiscoverEmptyCard extends StatelessWidget {
  const _HomeDiscoverEmptyCard();

  Future<void> _startWave(BuildContext context) async {
    try {
      final ok = await Get.find<PlayerController>().startRiffWave();
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          'riffWaveEmpty'.tr,
          size: SanckBarSize.MEDIUM,
        ));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        'networkError'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
  }

  void _openSearch() {
    Get.toNamed(
      ScreenNavigationSetup.searchScreen,
      id: ScreenNavigationSetup.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Material(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusMd),
          side: RiffTokens.hairlineBorder(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('discover'.tr, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'discoverEmptyDes'.tr,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _startWave(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                    label: Text('riffWave'.tr),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSearch,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textTheme.titleMedium?.color,
                      side: BorderSide(
                        color: theme.dividerColor.withOpacity(0.8),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.search, size: 18),
                    label: Text('search'.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resume the last saved queue when the player is idle.
class _ContinueListeningChip extends StatelessWidget {
  const _ContinueListeningChip();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<PlayerController>()) {
      return const SizedBox.shrink();
    }
    final player = Get.find<PlayerController>();
    return Obx(() {
      final idle =
          player.currentSong.value == null || player.initFlagForPlayer;
      if (player.showContinueListening.isFalse || !idle) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      final title = player.continueListeningTitle.value;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            side: RiffTokens.hairlineBorder(context),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            onTap: () => player.resumeSavedSession(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.play_circle_fill_rounded,
                      size: 22, color: theme.colorScheme.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'continueListening'.tr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (title.isNotEmpty)
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'close'.tr,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(Icons.close,
                        size: 18, color: theme.textTheme.bodySmall?.color),
                    onPressed: player.dismissContinueListening,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Resume the newest in-progress podcast episode from Home.
class _PodcastContinueChip extends StatelessWidget {
  const _PodcastContinueChip();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<PlayerController>()) {
      return const SizedBox.shrink();
    }
    final player = Get.find<PlayerController>();
    return Obx(() {
      final rows = PodcastProgressService.inProgress();
      final latest = latestPodcastContinue(rows);
      final episode = latest == null
          ? null
          : PodcastProgressService.toMediaItem(latest);
      if (episode == null ||
          !shouldShowPodcastContinueChip(
            hasEpisode: true,
            currentSongId: player.currentSong.value?.id,
            continueEpisodeId: episode.id,
          )) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            side: RiffTokens.hairlineBorder(context),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
            onTap: () {
              final queue = podcastContinueQueue(rows);
              if (queue.isEmpty) return;
              final pos =
                  PodcastProgressService.positionMs(queue.first.id) ?? 0;
              if (pos > 0) player.armResume(queue.first.id, pos);
              player.playPlayListSong(queue, 0);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.podcasts,
                      size: 22, color: theme.colorScheme.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'continueListening'.tr,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          episode.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_circle_fill_rounded,
                      size: 22, color: theme.colorScheme.secondary),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Soft strip when Home is showing cached shelves after a silent network miss.
class _OfflineHomeBanner extends StatelessWidget {
  const _OfflineHomeBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
          side: RiffTokens.hairlineBorder(context),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'retry'.tr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w700,
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
