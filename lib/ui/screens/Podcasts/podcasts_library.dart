import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/podcast_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/sort_widget.dart';
import 'podcast_category_screen.dart';
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

  // "Listeners of X also enjoy" discovery rows, loaded lazily when the search
  // field is focused (shown first in the search view, above the categories).
  final _discoveryRows = <String, List<Map<String, dynamic>>>{};
  List<String> _discoverySeeds = [];
  bool _discoveryLoaded = false;

  @override
  void initState() {
    super.initState();
    // Tapping the search field surfaces discovery + categories right away.
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        Get.find<LibraryPodcastsController>().enterSearchMode();
        _loadDiscoveryRows();
      }
    });
  }

  Future<void> _loadDiscoveryRows() async {
    if (_discoveryLoaded) return;
    _discoveryLoaded = true;
    final subs = Get.find<LibraryPodcastsController>().libraryPodcasts.toList();
    _discoverySeeds = subs.take(8).map((p) => p.title).toList();
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
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: controller.searchPodcasts,
              decoration: InputDecoration(
                hintText: 'searchPodcasts'.tr,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: Obx(() {
                  final hasQuery = controller.searchQuery.isNotEmpty ||
                      controller.hasSearched.isTrue;
                  if (!hasQuery) {
                    return IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () =>
                          controller.searchPodcasts(_searchCtrl.text),
                    );
                  }
                  return IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchCtrl.clear();
                      controller.clearSearch();
                    },
                  );
                }),
              ),
            ),
          ),
          // Inline nav: Inbox / Queue / Subscriptions swap the content below
          // instead of opening a separate screen.
          Padding(
            padding: const EdgeInsets.only(left: 3, right: 10, bottom: 2),
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
                    label: 'subscriptions'.tr,
                    section: 3),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Expanded(
            child: Obx(() {
              // ── Search results mode ─────────────────────────────
              if (controller.hasSearched.isTrue) {
                return _buildSearchBody(controller, itemWidth, itemHeight);
              }

              // ── Inline Inbox / Queue / Subscriptions ────────────
              if (_section == 1) {
                return const PodcastInboxScreen(embedded: true);
              }
              if (_section == 2) {
                return const PodcastQueueScreen(embedded: true);
              }
              if (_section == 3) {
                return const PodcastSubsScreen(embedded: true);
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
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // Leaving search mode if it was active.
          if (Get.find<LibraryPodcastsController>().hasSearched.isTrue) {
            _searchCtrl.clear();
            Get.find<LibraryPodcastsController>().clearSearch();
          }
          setState(() => _section = section);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? accent.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(active ? activeIcon : icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBody(LibraryPodcastsController controller,
      double itemWidth, double itemHeight) {
    return Obx(() {
      if (controller.isSearching.isTrue) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = controller.searchResults;
      final query = controller.searchQuery.value.trim();
      // No query yet → Spotify-style "Browse all" category tiles + suggestions.
      if (items.isEmpty && query.isEmpty) {
        return _browseView(controller, itemWidth, itemHeight);
      }
      if (items.isEmpty) {
        return Center(
          child: Text(
            'noResults'.tr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      }
      return _podcastGrid(
        controller, itemWidth, itemHeight,
        header: '${items.length} ${'items'.tr}',
        list: items.toList(),
      );
    });
  }

  // Distinct tile colours for the browse categories (Spotify-style).
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
        SliverPadding(
          padding: const EdgeInsets.only(right: 8, bottom: 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.9,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _categoryTile(genres[i]['id']!, genres[i]['name']!, i),
              childCount: genres.length,
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 5, top: 4, bottom: 4),
              child: Text('suggestions'.tr,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SliverLayoutBuilder(builder: (context, constraints) {
            final availableWidth = constraints.crossAxisExtent;
            final width = availableWidth > 300 && availableWidth < 394
                ? 310.0
                : availableWidth;
            final columns = (width / itemWidth).floor().clamp(2, 6);
            return SliverPadding(
              padding: const EdgeInsets.only(bottom: 200, top: 6),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: itemWidth / itemHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Center(
                    child: ContentListItem(
                        content: suggestions[index], showSimilarOnOpen: true),
                  ),
                  childCount: suggestions.length,
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _categoryTile(String genreId, String name, int i) {
    final color = _categoryColors[i % _categoryColors.length];
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Get.to(
          () => PodcastCategoryScreen(genreId: genreId, name: name)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
        ),
      ),
    );
  }

  Widget _podcastGrid(LibraryPodcastsController controller, double itemWidth,
      double itemHeight,
      {required String header, required List<Playlist> list}) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 5, top: 8, bottom: 4),
            child: Text(
              header,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        SliverLayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.crossAxisExtent;
              final width = availableWidth > 300 && availableWidth < 394
                  ? 310.0
                  : availableWidth;
              final columns = (width / itemWidth).floor().clamp(2, 6);
              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 200, top: 10),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: itemWidth / itemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Center(
                      child: ContentListItem(
                          content: list[index], showSimilarOnOpen: true),
                    ),
                    childCount: list.length,
                  ),
                ),
              );
            },
          ),
        ],
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
            itemBuilder: (_, i) => ContentListItem(content: podcasts[i]),
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
                  onTap: () => player.pushSongToQueue(ep),
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
          padding: const EdgeInsets.only(left: 5, top: 12, bottom: 6, right: 8),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            physics: const BouncingScrollPhysics(),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemCount: podcasts.length,
            itemBuilder: (_, i) => _ItunesPodcastCard(podcast: podcasts[i]),
          ),
        ),
      ],
    );
  }
}

/// Single square podcast card matching the tab's other cards (130×180).
class _ItunesPodcastCard extends StatelessWidget {
  const _ItunesPodcastCard({required this.podcast});
  final Map<String, dynamic> podcast;

  @override
  Widget build(BuildContext context) {
    final art = Thumbnail((podcast['artwork'] ?? '').toString()).high;
    return SizedBox(
      width: 130,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Get.to(() => PodcastEpisodesScreen(podcast: podcast)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CachedNetworkImage(
                imageUrl: art,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 120,
                  height: 120,
                  color: Theme.of(context).colorScheme.secondary.withOpacity(.3),
                  child: const Icon(Icons.podcasts, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (podcast['title'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              (podcast['author'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
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
