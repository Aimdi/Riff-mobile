import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/snackbar.dart';
import '/ui/widgets/sort_widget.dart';
import 'podcast_category_screen.dart';
import 'podcast_downloads_screen.dart';
import 'podcast_inbox_screen.dart';
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
        .take(8)
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
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5.0, right: 12),
            child: widget.isBottomNavActive
                ? const SizedBox(height: 10)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'podcasts'.tr,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
          ),
          // Inline nav: Inbox / Queue / Subs / Discover + AntennaPod-style
          // Refresh / Autoplay shortcuts on the right.
          Padding(
            padding: const EdgeInsets.only(left: 3, top: 6, right: 4, bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _navChip(
                            icon: Icons.inbox_outlined,
                            activeIcon: Icons.inbox,
                            label: 'podcastInbox'.tr,
                            section: 1),
                        _navChip(
                            icon: Icons.playlist_play,
                            activeIcon: Icons.playlist_play,
                            label: 'queue'.tr,
                            section: 2),
                        _navChip(
                            icon: Icons.subscriptions_outlined,
                            activeIcon: Icons.subscriptions,
                            label: 'subsShort'.tr,
                            section: 3),
                        _navChip(
                            icon: Icons.explore_outlined,
                            activeIcon: Icons.explore,
                            label: 'discover'.tr,
                            section: 4),
                        _navChip(
                            icon: Icons.download_outlined,
                            activeIcon: Icons.download,
                            label: 'downloads'.tr,
                            section: 5),
                      ],
                    ),
                  ),
                ),
                if (_section == 1)
                  IconButton(
                    tooltip: 'refreshInbox'.tr,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh_rounded, size: 22),
                    onPressed: () =>
                        setState(() => _inboxRefreshNonce++),
                  ),
                Obx(() {
                  final settings = Get.find<SettingsScreenController>();
                  final on =
                      settings.podcastContinuousPlaybackEnabled.value;
                  return IconButton(
                    tooltip: on
                        ? 'podcastAutoplayOn'.tr
                        : 'podcastAutoplayOff'.tr,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      on
                          ? Icons.playlist_play_rounded
                          : Icons.playlist_remove_rounded,
                      size: 22,
                      color: on
                          ? Theme.of(context).colorScheme.secondary
                          : null,
                    ),
                    onPressed: () =>
                        settings.togglePodcastContinuousPlayback(!on),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
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
                          : '${'popularWithListenersOf'.tr} $seed';
                      return SliverToBoxAdapter(
                        child: _SimilarPodcastsRow(
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

  /// A chip for the inline Inbox / Queue / Subscriptions nav.
  Widget _navChip({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int section,
  }) {
    final active = _section == section;
    final accent = Theme.of(context).colorScheme.secondary;
    final normal = Theme.of(context).textTheme.bodyMedium?.color;
    final color = active ? accent : normal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // Search state belongs to the Discover tab; reset it when leaving.
          if (section != 4 &&
              Get.find<LibraryPodcastsController>().hasSearched.isTrue) {
            _searchCtrl.clear();
            Get.find<LibraryPodcastsController>().clearSearch();
          }
          // Discover tab: load the "listeners also enjoy" rows.
          if (section == 4) _loadDiscoveryRows();
          setState(() => _section = section);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // M3-style indicator: a small pill behind the icon only, so
              // long labels below never get squeezed into ellipsis.
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                decoration: BoxDecoration(
                  color:
                      active ? accent.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(active ? activeIcon : icon, size: 22, color: color),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
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
          padding: const EdgeInsets.fromLTRB(5, 10, 12, 8),
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
              return const Center(child: CircularProgressIndicator());
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
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                        child: Text(
                          'youtubeChannels'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                        child: Text(
                          'youtubeChannelsDes'.tr,
                          style: Theme.of(context).textTheme.bodySmall,
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
                          padding: const EdgeInsets.symmetric(horizontal: 4),
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
                        padding:
                            const EdgeInsets.only(left: 5, top: 8, bottom: 4),
                        child: Text(
                          '${items.length} ${'items'.tr}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    SliverLayoutBuilder(builder: (context, constraints) {
                      final availableWidth = constraints.crossAxisExtent;
                      final width =
                          availableWidth > 300 && availableWidth < 394
                              ? 310.0
                              : availableWidth;
                      final columns =
                          (width / itemWidth).floor().clamp(2, 6);
                      return SliverPadding(
                        padding: const EdgeInsets.only(bottom: 200, top: 10),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisExtent: itemHeight + 12,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Center(
                              child: ContentListItem(
                                  content: items[index],
                                  showSimilarOnOpen: true),
                            ),
                            childCount: items.length,
                          ),
                        ),
                      );
                    }),
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
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Discovery: listeners of X also enjoy ────────────────
        if (discoverySeeds.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final seed = discoverySeeds[i];
                return _SimilarPodcastsRow(
                  title: '${'popularWithListenersOf'.tr} $seed',
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
        // ── Browse all: two rows of scrolling category chips ────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 5, top: 12, bottom: 8),
            child: Text('browseAll'.tr,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 100,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // rows
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 165, // chip width
              ),
              itemCount: genres.length,
              itemBuilder: (context, i) =>
                  _categoryChip(genres[i]['id']!, genres[i]['name']!, i),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  /// Compact tinted chip (colour-coded, not a Spotify colour block).
  Widget _categoryChip(String genreId, String name, int i) {
    final color = _categoryColors[i % _categoryColors.length];
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () async {
        if (shouldPlayPodcastShowOnTap()) {
          final ok = await playFirstPodcastInGenre(genreId);
          if (ok) return;
        }
        Get.to(() => PodcastCategoryScreen(genreId: genreId, name: name));
      },
      onLongPress: () => Get.to(
          () => PodcastCategoryScreen(genreId: genreId, name: name)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: color.withOpacity(0.20),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ),
          ],
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
        Padding(
          padding: const EdgeInsets.only(left: 5, top: 12, bottom: 6),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            physics: const BouncingScrollPhysics(),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
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
        Padding(
          padding: const EdgeInsets.only(left: 5, top: 8, bottom: 6),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            physics: const BouncingScrollPhysics(),
            itemCount: episodes.length,
            itemBuilder: (context, i) {
              final ep = episodes[i];
              return SizedBox(
                width: 130,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => player.playPlayListSong(episodes, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ImageWidget(song: ep, size: 120),
                      const SizedBox(height: 6),
                      Text(
                        ep.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (ep.artist != null)
                        Text(
                          ep.artist!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
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

/// "Popular with listeners of X" — a horizontal row of Apple-genre-similar
/// podcasts (plain maps: {title, author, artwork, feedUrl}). Tapping a card
/// opens its episode list (PodcastEpisodesScreen), which streams straight from
/// the RSS enclosure.
/// Compact "Similar podcasts" strip (smaller than featured carousel cards).
class _SimilarPodcastsRow extends StatelessWidget {
  const _SimilarPodcastsRow({required this.title, required this.podcasts});
  final String title;
  final List<Map<String, dynamic>> podcasts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 10, bottom: 4, right: 8),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            physics: const BouncingScrollPhysics(),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: podcasts.length,
            itemBuilder: (_, i) => _ItunesPodcastCard(podcast: podcasts[i]),
          ),
        ),
      ],
    );
  }
}

/// Compact square podcast chip for similar / suggestion rows.
class _ItunesPodcastCard extends StatelessWidget {
  const _ItunesPodcastCard({required this.podcast});
  final Map<String, dynamic> podcast;

  static const double _tile = 64;

  @override
  Widget build(BuildContext context) {
    final art = Thumbnail((podcast['artwork'] ?? '').toString()).medium;
    return SizedBox(
      width: _tile,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          if (shouldPlayPodcastShowOnTap()) {
            final ok = await playPodcastShow(podcast);
            if (ok) return;
          }
          Get.to(() => PodcastEpisodesScreen(podcast: podcast));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: art,
                width: _tile,
                height: _tile,
                memCacheWidth:
                    (_tile * MediaQuery.devicePixelRatioOf(context)).round(),
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: _tile,
                  height: _tile,
                  color: Theme.of(context).colorScheme.secondary.withOpacity(.3),
                  child: const Icon(Icons.podcasts, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (podcast['title'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
            ),
          ],
        ),
      ),
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
