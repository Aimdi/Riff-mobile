import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/discovery/discovery_types.dart';
import '/services/podcast_service.dart';
import '/services/wizestream_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/utils/riff_tokens.dart';
import '/ui/utils/theme_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/sort_widget.dart';
import '/ui/navigator.dart';
import '../Home/home_layout.dart';
import 'podcast_category_screen.dart';
import 'podcast_downloads_screen.dart';
import 'podcast_layout.dart';
import '/services/podcast_library.dart';
import 'podcast_bookmarks_ui.dart';
import 'podcast_inbox_screen.dart';
import 'podcast_queue_controller.dart';
import 'podcast_queue_screen.dart';
import 'podcast_subs_screen.dart';
import 'podcasts_library_controller.dart';
import 'podcasts_screen.dart';

class PodcastsLibraryWidget extends StatefulWidget {
  const PodcastsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  State<PodcastsLibraryWidget> createState() => _PodcastsLibraryWidgetState();
}

class _PodcastsLibraryWidgetState extends State<PodcastsLibraryWidget> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // Inline section shown in the content area: 1 = Inbox (default), 2 = Queue,
  // 3 = Subscriptions. Discovery now lives inside the search view.
  int _section = 1;
  int _inboxRefreshNonce = 0;

  // "Listeners of X also enjoy" discovery rows, loaded lazily when the search
  // field is focused (shown first in the search view, above the categories).
  final _discoveryRows = <String, List<Map<String, dynamic>>>{};
  List<String> _discoverySeeds = [];
  bool _discoveryLoaded = false;

  Future<void> _loadDiscoveryRows() async {
    if (_discoveryLoaded) return;
    _discoveryLoaded = true;
    // Seed the "listeners of X also enjoy" rows from BOTH subscription
    // stores: YT-Music library shows and iTunes/RSS subscriptions.
    final ytTitles = Get.find<LibraryPodcastsController>()
        .libraryPodcasts
        .map((p) => p.title)
        .toList();
    final rssTitles =
        PodcastService.subscriptions.map((s) => '${s['title'] ?? ''}').toList();
    _discoverySeeds = {...ytTitles, ...rssTitles}
        .where((t) => t.trim().isNotEmpty)
        .take(3)
        .toList();
    await Future.wait(_discoverySeeds.map((title) async {
      try {
        final res = await PodcastService.similar(title);
        if (res.isNotEmpty) _discoveryRows[title] = res;
      } catch (_) {}
    }));
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Picks up a WizeStream installed since launch.
    if (GetPlatform.isAndroid) WizeStream.refresh();
    // "After 24 hours" downloads go once their day is up, even if nothing
    // new has been played since.
    PodcastLibrary.sweepDownloads(
        currentId: Get.find<PlayerController>().currentSong.value?.id);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<LibraryPodcastsController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    const double itemHeight = 180;
    const double itemWidth = 130;

    return Padding(
      padding: widget.isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isBottomNavActive) _header(context),
          _tabs(context),
          const SizedBox(height: 4),
          Expanded(
            // Plain builder: section switching is setState-driven. (An Obx
            // here would throw at runtime — its builder reads no Rx values.)
            child: Builder(builder: (context) {
              // ── Inline Inbox / Queue / Subs / Discover ──────────
              if (_section == 1) {
                return PodcastInboxScreen(
                  embedded: true,
                  refreshNonce: _inboxRefreshNonce,
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 2) {
                return PodcastQueueScreen(
                  embedded: true,
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 3) {
                return PodcastSubsScreen(
                  embedded: true,
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 4) {
                // Discover tab: search + discovery rows + categories.
                return _discoverView(controller, itemWidth, itemHeight);
              }
              if (_section == 6) {
                return const PodcastBookmarksScreen(embedded: true);
              }
              if (_section == 5) {
                return PodcastDownloadsScreen(
                  embedded: true,
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }

              // ── Fallback (unused: default section is Inbox) ─────
              return RefreshIndicator(
                onRefresh: () => controller.loadDiscovery(force: true),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  slivers: [
                    // ── Discovery ──────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.only(left: 5, top: 8, right: 8),
                        child: Row(
                          children: [
                            Text(
                              'discoverPodcasts'.tr,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Obx(() {
                              if (controller.isDiscoveryLoading.isTrue) {
                                return const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                );
                              }
                              return IconButton(
                                tooltip: 'retry'.tr,
                                icon: const Icon(Icons.refresh, size: 20),
                                onPressed: () =>
                                    controller.loadDiscovery(force: true),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    Obx(() {
                      if (controller.discoveryError.isTrue &&
                          controller.topEpisodes.isEmpty &&
                          controller.featuredPodcasts.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Column(
                                children: [
                                  Text('networkError1'.tr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: () =>
                                        controller.loadDiscovery(force: true),
                                    child: Text('retry'.tr),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }),
                    // Top episodes row
                    Obx(() {
                      if (controller.topEpisodes.isEmpty) {
                        return const SliverToBoxAdapter(
                            child: SizedBox.shrink());
                      }
                      return SliverToBoxAdapter(
                        child: _EpisodeDiscoveryRow(
                          title: 'topEpisodes'.tr,
                          episodes: controller.topEpisodes.toList(),
                        ),
                      );
                    }),
                    // Featured podcasts row
                    Obx(() {
                      if (controller.featuredPodcasts.isEmpty) {
                        return const SliverToBoxAdapter(
                            child: SizedBox.shrink());
                      }
                      return SliverToBoxAdapter(
                        child: _PodcastCarousel(
                          title: 'featuredPodcasts'.tr,
                          podcasts: controller.featuredPodcasts.toList(),
                        ),
                      );
                    }),
                    // Similar podcasts row ("Popular with listeners of X")
                    Obx(() {
                      if (controller.similarPodcasts.isEmpty) {
                        return const SliverToBoxAdapter(
                            child: SizedBox.shrink());
                      }
                      final seed = controller.similarSeedTitle.value;
                      final title = seed.isEmpty
                          ? 'similarPodcasts'.tr
                          : seed;
                      return SliverToBoxAdapter(
                        child: _SimilarPodcastsRow(
                          kicker: seed.isEmpty ? null : 'Because you follow',
                          title: title,
                          podcasts: controller.similarPodcasts.toList(),
                        ),
                      );
                    }),
                    // ── Library ────────────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 5, top: 16),
                        child: Text(
                          'libPodcasts'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Obx(
                        () => SortWidget(
                          tag: 'LibPodcastSort',
                          screenController: controller,
                          isAdditionalOperationRequired: false,
                          isSearchFeatureRequired: true,
                          itemCountTitle:
                              '${controller.libraryPodcasts.length} ${'items'.tr}',
                          requiredSortTypes: buildSortTypeSet(),
                          onSort: controller.onSort,
                          onSearch: controller.onSearch,
                          onSearchClose: controller.onSearchClose,
                          onSearchStart: controller.onSearchStart,
                        ),
                      ),
                    ),
                    Obx(() {
                      final items = controller.libraryPodcasts;
                      if (items.isEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'noPodcastsBookmarked'.tr,
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      }
                      return SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final availableWidth = constraints.crossAxisExtent;
                          final width =
                              availableWidth > 300 && availableWidth < 394
                                  ? 310.0
                                  : availableWidth;
                          final columns =
                              (width / itemWidth).floor().clamp(2, 6);
                          return SliverPadding(
                            padding: const EdgeInsets.only(
                                bottom: 200, top: 10, left: 0, right: 0),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                childAspectRatio: itemWidth / itemHeight,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => Center(
                                  child: GestureDetector(
                                    // Long-press to file this show into a folder.
                                    onLongPress: () => showPodcastFolderSheet(
                                        context, items[index]),
                                    child: ContentListItem(
                                      content: items[index],
                                      isLibraryItem: true,
                                    ),
                                  ),
                                ),
                                childCount: items.length,
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// "Podcasts" title with the tab's shortcuts (refresh the inbox,
  /// autoplay next episode) on the right.
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(HomeLayout.gutter, 0, 4, 6),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'podcasts'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_section == 1)
              IconButton(
                tooltip: 'refreshInbox'.tr,
                icon: const Icon(Icons.refresh_rounded, size: 22),
                onPressed: () => setState(() => _inboxRefreshNonce++),
              ),
            Obx(() {
              final settings = Get.find<SettingsScreenController>();
              final on = settings.podcastContinuousPlaybackEnabled.value;
              return IconButton(
                tooltip: on ? 'podcastAutoplayOn'.tr : 'podcastAutoplayOff'.tr,
                icon: Icon(
                  on
                      ? Icons.playlist_play_rounded
                      : Icons.playlist_remove_rounded,
                  size: 24,
                  color: on ? Theme.of(context).colorScheme.secondary : null,
                ),
                onPressed: () => settings.togglePodcastContinuousPlayback(!on),
              );
            }),
            IconButton(
              tooltip: 'podcastSettings'.tr,
              icon: const Icon(Icons.settings_outlined, size: 22),
              onPressed: () => Get.toNamed(
                  ScreenNavigationSetup.podcastSettingsScreen,
                  id: ScreenNavigationSetup.id),
            ),
          ],
        ),
      ),
    );
  }

  /// Inbox · Queue · Subscriptions · Discover · Downloads · Bookmarks as
  /// pill tabs.
  Widget _tabs(BuildContext context) {
    final tabs = <(int, String)>[
      (1, 'podcastInbox'.tr),
      (2, 'queue'.tr),
      (3, 'subscriptions'.tr),
      (4, 'discover'.tr),
      (5, 'downloads'.tr),
      (6, 'bookmarks'.tr),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (section, label) = tabs[i];
          if (section != 2) return _tab(context, section, label, null);
          // Queue shows how many episodes are waiting.
          return Obx(() {
            final n = Get.find<PodcastQueueController>().queue.length;
            return _tab(context, section, label, n > 0 ? '$n' : null);
          });
        },
      ),
    );
  }

  Widget _tab(BuildContext context, int section, String label, String? count) {
    final active = _section == section;
    final accent = Theme.of(context).colorScheme.secondary;
    final fg = active
        ? RiffSurfaces.voidBlack
        : Theme.of(context).textTheme.titleMedium?.color;
    return Material(
      color: active ? accent : homeTileColor(context),
      shape: StadiumBorder(side: active ? BorderSide.none : homeTileBorder(context)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(section),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label),
                if (count != null)
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(color: fg?.withOpacity(0.6)),
                  ),
              ]),
              maxLines: 1,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(int section) {
    // Search state belongs to the Discover tab; reset it when leaving.
    if (section != 4 &&
        Get.find<LibraryPodcastsController>().hasSearched.isTrue) {
      _searchCtrl.clear();
      Get.find<LibraryPodcastsController>().clearSearch();
    }
    // Discover tab: load the "listeners also enjoy" rows.
    if (section == 4) _loadDiscoveryRows();
    setState(() => _section = section);
  }

  /// Discover tab: a rounded search bar on top; below it either the search
  /// results or the browse view (discovery rows + categories + suggestions).
  Widget _discoverView(LibraryPodcastsController controller, double itemWidth,
      double itemHeight) {
    final theme = Theme.of(context);
    final hintColor = theme.textTheme.bodySmall?.color?.withOpacity(0.6);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              HomeLayout.gutter, 6, HomeLayout.gutter, 4),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: controller.searchPodcasts,
            decoration: InputDecoration(
              hintText: 'searchPodcastsOrYoutube'.tr,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(color: hintColor),
              prefixIcon: Icon(Icons.search, color: hintColor),
              filled: true,
              fillColor: theme.colorScheme.onSurface.withOpacity(0.07),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              // All three states set explicitly: the app theme's focused
              // underline would otherwise leak under the pill.
              border: _searchBorder,
              enabledBorder: _searchBorder,
              focusedBorder: _searchBorder,
              suffixIcon: Obx(() {
                final active = controller.hasSearched.isTrue ||
                    controller.searchQuery.isNotEmpty;
                if (!active) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(Icons.close, color: hintColor),
                  onPressed: () {
                    _searchCtrl.clear();
                    controller.clearSearch();
                  },
                );
              }),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            if (controller.isSearching.isTrue) {
              return const SongListShimmer(itemCount: 8, topPadding: 8);
            }
            final items = controller.searchResults;
            final channels = controller.channelSearchResults;
            final query = controller.searchQuery.value.trim();
            if (controller.hasSearched.isTrue && query.isNotEmpty) {
              if (items.isEmpty && channels.isEmpty) {
                return Center(
                  child: Text(
                    'noResults'.tr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  if (channels.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            HomeLayout.gutter, 12, HomeLayout.gutter, 2),
                        child: Text(
                          'youtubeChannels'.tr,
                          style: homeSectionTitleStyle(context),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            HomeLayout.gutter, 0, HomeLayout.gutter, 10),
                        child: Text(
                          'youtubeChannelsDes'.tr,
                          style: homeCardSubtitleStyle(context),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        // ContentListItem is a fixed 180h tile — Follow sits
                        // on top so it stays tappable (Column under it was
                        // clipped / untappable).
                        height: itemHeight + 8,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: HomeLayout.gutter - 4),
                          itemCount: channels.length,
                          itemBuilder: (context, i) {
                            final ch = channels[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Obx(() {
                                final subscribed = controller.libraryPodcasts
                                    .any((p) => p.playlistId == ch.playlistId);
                                return SizedBox(
                                  width: 130,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ContentListItem(
                                        content: ch,
                                        isLibraryItem: subscribed,
                                      ),
                                      Positioned(
                                        left: 4,
                                        right: 4,
                                        top: 86,
                                        child: PodcastFollowButton(
                                          compact: true,
                                          following: subscribed,
                                          onPressed: () async {
                                            if (subscribed) {
                                              await controller
                                                  .removeFromLibrary(
                                                      ch.playlistId);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(snackbar(
                                                context,
                                                'removeFromLib'.tr,
                                                size: SanckBarSize.MEDIUM,
                                              ));
                                              return;
                                            }
                                            final pl = await controller
                                                .subscribeYoutubeChannel(
                                              ch.playlistId,
                                              seed: ch,
                                            );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(snackbar(
                                              context,
                                              pl != null
                                                  ? 'subscribedAsPodcast'.tr
                                                  : 'operationFailed'.tr,
                                              size: SanckBarSize.MEDIUM,
                                            ));
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                  if (items.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            HomeLayout.gutter, 16, HomeLayout.gutter, 0),
                        child: Text(
                          '${items.length} ${'items'.tr}',
                          style: homeCardSubtitleStyle(context)
                              .copyWith(fontSize: 13),
                        ),
                      ),
                    ),
                    // One row per show: cover, full two-line title, host
                    // and Subscribe. Tapping opens the show; the cover's
                    // play button starts the latest episode.
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 6, bottom: 200),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _ShowResultRow(
                            key: ValueKey(items[index].playlistId),
                            show: items[index],
                            controller: controller,
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                  ] else
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            }
            return _browseView(controller, itemWidth, itemHeight);
          }),
        ),
      ],
    );
  }

  static final _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(26),
    borderSide: BorderSide.none,
  );

  // Accent colours for the browse category chips.
  static const _categoryColors = <Color>[
    Color(0xFF1E3264),
    Color(0xFF8D67AB),
    Color(0xFFE13300),
    Color(0xFF148A08),
    Color(0xFFD84000),
    Color(0xFF0D73EC),
    Color(0xFFBA5D07),
    Color(0xFF477D95),
    Color(0xFF503750),
    Color(0xFF777777),
    Color(0xFF8C1932),
    Color(0xFF1E3264),
    Color(0xFF608108),
    Color(0xFFA56752),
    Color(0xFFE8115B),
    Color(0xFF27856A),
  ];

  /// Search-focus landing: first the "listeners of X also enjoy" discovery
  /// scrollwheels, then Apple-Podcasts category tiles, then featured
  /// suggestions.
  Widget _browseView(LibraryPodcastsController controller, double itemWidth,
      double itemHeight) {
    const genres = PodcastService.podcastGenres;
    final suggestions = controller.featuredPodcasts.toList();
    final discoverySeeds =
        _discoverySeeds.where(_discoveryRows.containsKey).toList();
    final showYoutube = controller.youtubePodcastsEnabled;
    final ytEpisodes = controller.ytPopularEpisodes.toList();
    final ytShows = controller.ytPopularShows.toList();
    if (showYoutube &&
        ytShows.isEmpty &&
        ytEpisodes.isEmpty &&
        controller.isYtLoading.isFalse) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => controller.loadYoutubePodcasts());
    }
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── YouTube Podcasts: popular episodes (video) + shows ──
        if (showYoutube && ytEpisodes.isNotEmpty)
          SliverToBoxAdapter(
            child: _VideoEpisodeRow(
              title: 'ytPopularEpisodes'.tr,
              episodes: ytEpisodes,
            ),
          ),
        if (showYoutube && ytShows.isNotEmpty)
          SliverToBoxAdapter(
            child: _PodcastCarousel(
                title: 'ytPopularPodcasts'.tr, podcasts: ytShows),
          ),
        // ── Discovery: listeners of X also enjoy ────────────────
        if (discoverySeeds.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final seed = discoverySeeds[i];
                return _SimilarPodcastsRow(
                  kicker: 'Because you follow',
                  title: seed,
                  podcasts: _discoveryRows[seed]!,
                );
              },
              childCount: discoverySeeds.length,
            ),
          ),
        // ── Suggestions: one compact scrollwheel ────────────────
        if (suggestions.isNotEmpty)
          SliverToBoxAdapter(
            child: _PodcastCarousel(
                title: 'suggestions'.tr, podcasts: suggestions),
          ),
        // ── Browse all: two-column grid of category tiles ───────
        SliverToBoxAdapter(child: HomeSectionHeader('browseAll'.tr)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
              mainAxisSpacing: HomeLayout.tileGap,
              crossAxisSpacing: HomeLayout.tileGap,
              mainAxisExtent:
                  MediaQuery.textScalerOf(context).scale(HomeLayout.tileHeight),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) =>
                  _categoryChip(genres[i]['id']!, genres[i]['name']!, i),
              childCount: genres.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  /// Category tile: a solid colour block with the genre name.
  Widget _categoryChip(String genreId, String name, int i) {
    final color = _categoryColors[i % _categoryColors.length];
    return Material(
      color: Color.alphaBlend(Colors.black.withOpacity(0.18), color),
      borderRadius: BorderRadius.circular(RiffTokens.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (shouldPlayPodcastShowOnTap()) {
            final ok = await playFirstPodcastInGenre(genreId);
            if (ok) return;
          }
          Get.to(() => PodcastCategoryScreen(genreId: genreId, name: name));
        },
        onLongPress: () => Get.to(
            () => PodcastCategoryScreen(genreId: genreId, name: name)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PodcastCarousel extends StatelessWidget {
  const _PodcastCarousel({required this.title, required this.podcasts});
  final String title;
  final List<Playlist> podcasts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title),
        SizedBox(
          height:
              ContentListItem.heightFor(context, ContentListItem.defaultSize),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            physics: const BouncingScrollPhysics(),
            separatorBuilder: (_, __) =>
                const SizedBox(width: HomeLayout.cardGap),
            itemCount: podcasts.length,
            itemBuilder: (_, i) =>
                ContentListItem(content: podcasts[i], showSimilarOnOpen: true),
          ),
        ),
      ],
    );
  }
}

class _EpisodeDiscoveryRow extends StatelessWidget {
  const _EpisodeDiscoveryRow({required this.title, required this.episodes});
  final String title;
  final List<MediaItem> episodes;

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title),
        HomeShelf(
          cardSize: HomeLayout.shelfCard,
          itemCount: episodes.length,
          itemBuilder: (context, i) {
            final ep = episodes[i];
            return HomeShelfCard(
              size: HomeLayout.shelfCard,
              art: ImageWidget(song: ep, size: HomeLayout.shelfCard),
              title: ep.title,
              subtitle: ep.artist ?? '',
              onTap: () async {
                if (await openInWizeStreamIfPreferred(ep)) return;
                final ok = await player.playPlayListSong(episodes, i);
                if (!ok) snackOperationFailed();
              },
            );
          },
        ),
      ],
    );
  }
}

/// YouTube podcast episodes as 16:9 video cards (they are videos, so a
/// square crop would cut faces and titles out of the thumbnail).
class _VideoEpisodeRow extends StatelessWidget {
  const _VideoEpisodeRow({required this.title, required this.episodes});
  final String title;
  final List<MediaItem> episodes;

  static String _clock(Duration? d) {
    if (d == null || d == Duration.zero) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final theme = Theme.of(context);
    const cardWidth = 256.0;
    final scaler = MediaQuery.textScalerOf(context);
    const thumbHeight = cardWidth * 9 / 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title, top: 12),
        SizedBox(
          // Thumb + two-line title + one meta line.
          height: thumbHeight +
              8 +
              scaler.scale(13.5) * 1.2 * 2 +
              2 +
              scaler.scale(12) * 1.25 +
              6,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
            physics: const BouncingScrollPhysics(),
            itemCount: episodes.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: HomeLayout.cardGap),
            itemBuilder: (context, i) {
              final ep = episodes[i];
              final clock = _clock(ep.duration);
              final art = ep.artUri?.toString() ?? '';
              return SizedBox(
                width: cardWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onLongPress: () => showAddToQueueSheet(context, ep),
                  onTap: () async {
                    if (await openInWizeStreamIfPreferred(ep)) return;
                    final ok = await player.playPlayListSong(episodes, i,
                        source: DiscoverySource.podcast);
                    if (!ok) snackOperationFailed();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: cardWidth,
                          height: thumbHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (art.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: art,
                                  httpHeaders: kCoverImageHeaders,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 480,
                                  errorWidget: (_, __, ___) =>
                                      ColoredBox(color: theme.cardColor),
                                  placeholder: (_, __) =>
                                      ColoredBox(color: theme.cardColor),
                                )
                              else
                                ColoredBox(color: theme.cardColor),
                              if (clock.isNotEmpty)
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.75),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      clock,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ep.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardTitleStyle(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        episodeMetaLine(
                            [ep.artist, '${ep.extras?['date'] ?? ''}']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardSubtitleStyle(context),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "Because you follow X" — Apple-genre-similar podcasts (plain maps:
/// {title, author, artwork, feedUrl}). Tapping plays the show, or opens its
/// episode list when that fails.
class _SimilarPodcastsRow extends StatelessWidget {
  const _SimilarPodcastsRow({
    required this.title,
    required this.podcasts,
    this.kicker,
  });
  final String title;
  final String? kicker;
  final List<Map<String, dynamic>> podcasts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kicker != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                HomeLayout.gutter, HomeLayout.sectionTop, HomeLayout.gutter, 0),
            child: Text(
              kicker!.toUpperCase(),
              style: homeCardSubtitleStyle(context).copyWith(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        HomeSectionHeader(title,
            top: kicker != null ? 2 : HomeLayout.sectionTop),
        HomeShelf(
          cardSize: HomeLayout.shelfCard,
          itemCount: podcasts.length,
          itemBuilder: (context, i) {
            final podcast = podcasts[i];
            return HomeShelfCard(
              size: HomeLayout.shelfCard,
              art: PodcastArt(
                url: Thumbnail((podcast['artwork'] ?? '').toString()).medium,
                size: HomeLayout.shelfCard,
              ),
              title: (podcast['title'] ?? '').toString(),
              subtitle: (podcast['author'] ?? '').toString(),
              onTap: () async {
                if (shouldPlayPodcastShowOnTap()) {
                  final ok = await playPodcastShow(podcast);
                  if (ok) return;
                }
                Get.to(() => PodcastEpisodesScreen(podcast: podcast));
              },
              onLongPress: () =>
                  Get.to(() => PodcastEpisodesScreen(podcast: podcast)),
            );
          },
        ),
      ],
    );
  }
}

/// Bookmark / unbookmark helper used from playlist screen when content is a podcast.
Future<void> togglePodcastLibrary(Playlist podcast, {required bool add}) async {
  final c = Get.find<LibraryPodcastsController>();
  if (add) {
    await c.addToLibrary(podcast);
  } else {
    await c.removeFromLibrary(podcast.playlistId);
  }
}

/// A podcast search result: cover, two-line title, host and Subscribe.
class _ShowResultRow extends StatelessWidget {
  const _ShowResultRow(
      {super.key, required this.show, required this.controller});
  final Playlist show;
  final LibraryPodcastsController controller;

  void _open() => Get.toNamed(ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id,
      arguments: [show, show.playlistId, true]);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            HomeLayout.gutter, 8, HomeLayout.gutter, 8),
        child: Row(
          children: [
            PodcastArt(url: show.thumbnailUrl, size: 72),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    show.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: homeCardTitleStyle(context)
                        .copyWith(fontSize: 15, height: 1.25),
                  ),
                  if ((show.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      show.description!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: homeCardSubtitleStyle(context)
                          .copyWith(fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Obx(() {
              final subscribed = controller.libraryPodcasts
                  .any((p) => p.playlistId == show.playlistId);
              // Quiet in a list: outlined + to subscribe, accent check once
              // subscribed (the show page has the full Subscribe button).
              return IconButton(
                tooltip: subscribed ? 'subscribed'.tr : 'subscribe'.tr,
                onPressed: () async {
                  if (subscribed) {
                    await controller.removeFromLibrary(show.playlistId);
                  } else {
                    await controller.addToLibrary(show);
                  }
                },
                icon: Icon(
                  subscribed
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 28,
                  color: subscribed
                      ? Theme.of(context).colorScheme.secondary
                      : homeMutedColor(context),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
