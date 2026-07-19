import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/sort_widget.dart';
import 'podcasts_library_controller.dart';

class PodcastsLibraryWidget extends StatefulWidget {
  const PodcastsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  State<PodcastsLibraryWidget> createState() => _PodcastsLibraryWidgetState();
}

class _PodcastsLibraryWidgetState extends State<PodcastsLibraryWidget> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
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
          Expanded(
            child: Obx(() {
              // ── Search results mode ─────────────────────────────
              if (controller.hasSearched.isTrue) {
                return _buildSearchBody(controller, itemWidth, itemHeight);
              }

              // ── Discovery + library mode ────────────────────────
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
                                  child: ContentListItem(
                                    content: items[index],
                                    isLibraryItem: true,
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

  Widget _buildSearchBody(LibraryPodcastsController controller,
      double itemWidth, double itemHeight) {
    return Obx(() {
      if (controller.isSearching.isTrue) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = controller.searchResults;
      if (items.isEmpty) {
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 5, top: 8, bottom: 4),
              child: Text(
                '${items.length} ${'items'.tr}',
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
                      child: ContentListItem(content: items[index]),
                    ),
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      );
    });
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

/// Bookmark / unbookmark helper used from playlist screen when content is a podcast.
Future<void> togglePodcastLibrary(Playlist podcast, {required bool add}) async {
  final c = Get.find<LibraryPodcastsController>();
  if (add) {
    await c.addToLibrary(podcast);
  } else {
    await c.removeFromLibrary(podcast.playlistId);
  }
}
