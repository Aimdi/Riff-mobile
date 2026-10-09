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
import '/ui/theme/palettes/podcasts.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/content_list_widget_item.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/podcast_play.dart';
import '/ui/widgets/shimmer_widgets/song_list_shimmer.dart';
import '/ui/widgets/snackbar.dart';
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
import '/ui/theme/riff_text_metrics.dart';
import '/ui/widgets/riff_header_bar.dart';
import '/ui/widgets/song_list_tile.dart' show RiffRowHairline;

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

  /// The Inbox's library filter (New, In progress, …), picked from the
  /// selected Inbox chip's menu; null is the plain Inbox. Kept while other
  /// sections are open.
  EpisodeFilter? _inboxFilter;

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

    return Padding(
      padding: widget.isBottomNavActive
          ? const EdgeInsets.only(top: 10)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isBottomNavActive) _header(context),
          _tabs(context),
          const SizedBox(height: RiffSpacing.xs),
          Expanded(
            // Plain builder: section switching is setState-driven. (An Obx
            // here would throw at runtime — its builder reads no Rx values.)
            child: RiffScrollUnder(child: Builder(builder: (context) {
              // ── Inline Inbox / Queue / Subs / Discover ──────────
              if (_section == 1) {
                return PodcastInboxScreen(
                  refreshNonce: _inboxRefreshNonce,
                  filter: _inboxFilter,
                  onFilterChanged: _setInboxFilter,
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 2) {
                return PodcastQueueScreen(
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 3) {
                return PodcastSubsScreen(
                  onDiscover: () {
                    _loadDiscoveryRows();
                    setState(() => _section = 4);
                  },
                );
              }
              if (_section == 4) {
                // Discover tab: search + discovery rows + categories.
                return _discoverView(controller, itemHeight);
              }
              if (_section == 6) {
                return const PodcastBookmarksScreen(embedded: true);
              }
              // Section 5: Downloads (the tabs offer only 1–6).
              return PodcastDownloadsScreen(
                onDiscover: () {
                  _loadDiscoveryRows();
                  setState(() => _section = 4);
                },
              );
            })),
          ),
        ],
      ),
    );
  }

  /// "Podcasts" title with the tab's shortcuts (refresh the inbox,
  /// autoplay next episode) on the right.
  Widget _header(BuildContext context) {
    return RiffHeaderBar(
        hairline: false,
        child: Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              right: RiffSpacing.xs,
              bottom: RiffSpacing.sm),
          child: SizedBox(
            height: RiffComponentSizes.iconHit,
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
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => setState(() => _inboxRefreshNonce++),
                  ),
                Obx(() {
                  final settings = Get.find<SettingsScreenController>();
                  final on = settings.podcastContinuousPlaybackEnabled.value;
                  return IconButton(
                    tooltip:
                        on ? 'podcastAutoplayOn'.tr : 'podcastAutoplayOff'.tr,
                    icon: Icon(
                      on
                          ? Icons.playlist_play_rounded
                          : Icons.playlist_remove_rounded,
                      color: on ? Theme.of(context).colorScheme.primary : null,
                    ),
                    onPressed: () =>
                        settings.togglePodcastContinuousPlayback(!on),
                  );
                }),
                IconButton(
                  tooltip: 'podcastStats'.tr,
                  icon: const Icon(Icons.insights_rounded),
                  onPressed: () => Get.toNamed(
                      ScreenNavigationSetup.podcastStatsScreen,
                      id: ScreenNavigationSetup.id),
                ),
                IconButton(
                  tooltip: 'podcastSettings'.tr,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Get.toNamed(
                      ScreenNavigationSetup.podcastSettingsScreen,
                      id: ScreenNavigationSetup.id),
                ),
              ],
            ),
          ),
        ));
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
      height: RiffComponentSizes.buttonCompact,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: RiffSpacing.sm),
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

  /// One section pill, styled as a §5.6 chip: transparent with a divider
  /// outline; the active one has an accentMuted fill, accent outline and
  /// accent label. The active Inbox pill also names its filter and has a
  /// caret: tapping it again opens the filter menu.
  Widget _tab(BuildContext context, int section, String label, String? count) {
    final active = _section == section;
    final filters = active && section == 1;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fg = active ? accent : theme.colorScheme.onSurface;
    final text = Text.rich(
      TextSpan(children: [
        TextSpan(text: filters ? inboxChipLabel(_inboxFilter) : label),
        if (count != null)
          TextSpan(
            text: '  $count',
            style: TextStyle(
                color: active ? accent : theme.colorScheme.onSurfaceVariant),
          ),
      ]),
      maxLines: 1,
      style: theme.textTheme.labelMedium?.copyWith(color: fg),
    );
    final pill = Builder(
      builder: (chip) => Material(
        color: active ? RiffColors.of(context).accentMuted : Colors.transparent,
        shape: StadiumBorder(
            side: BorderSide(
                color: active ? accent : theme.dividerColor, width: 0)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: filters
              ? () => showInboxFilterMenu(chip,
                  current: _inboxFilter, onSelected: _setInboxFilter)
              : () => _select(section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
            child: Center(
              child: filters
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text,
                        Icon(Icons.expand_more_rounded,
                            size: RiffComponentSizes.chipChevron, color: fg),
                      ],
                    )
                  : text,
            ),
          ),
        ),
      ),
    );
    return filters ? Tooltip(message: 'filterInbox'.tr, child: pill) : pill;
  }

  void _setInboxFilter(EpisodeFilter? filter) {
    if (mounted) setState(() => _inboxFilter = filter);
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
  Widget _discoverView(
      LibraryPodcastsController controller, double itemHeight) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hintColor = scheme.onSurfaceVariant;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: HomeLayout.gutter,
              top: RiffSpacing.sm,
              right: HomeLayout.gutter,
              bottom: RiffSpacing.xs),
          // §5.8: surface1 pill, 40 tall, no border at rest, 1 px accent
          // ring on focus.
          child: SizedBox(
            height: RiffComponentSizes.searchField,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: controller.searchPodcasts,
              style:
                  theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'searchPodcastsOrYoutube'.tr,
                hintStyle:
                    theme.textTheme.bodyLarge?.copyWith(color: hintColor),
                prefixIcon: Icon(Icons.search,
                    size: RiffComponentSizes.trailingIcon, color: hintColor),
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                // All three states set explicitly: the app theme's focused
                // underline would otherwise leak under the pill.
                border: _searchBorder,
                enabledBorder: _searchBorder,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RiffRadii.pill),
                  borderSide: BorderSide(color: scheme.primary, width: 1),
                ),
                suffixIcon: Obx(() {
                  final active = controller.hasSearched.isTrue ||
                      controller.searchQuery.isNotEmpty;
                  if (!active) return const SizedBox.shrink();
                  return IconButton(
                    icon: Icon(Icons.close,
                        size: RiffComponentSizes.trailingIcon,
                        color: hintColor),
                    onPressed: () {
                      _searchCtrl.clear();
                      controller.clearSearch();
                    },
                  );
                }),
              ),
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
                        padding: const EdgeInsets.only(
                            left: HomeLayout.gutter,
                            top: RiffSpacing.md,
                            right: HomeLayout.gutter,
                            bottom: RiffSpacing.xxs),
                        child: Text(
                          'youtubeChannels'.tr,
                          style: homeSectionTitleStyle(context),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                            left: HomeLayout.gutter,
                            right: HomeLayout.gutter,
                            bottom: RiffSpacing.md),
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
                        padding: const EdgeInsets.only(
                            left: HomeLayout.gutter,
                            top: RiffSpacing.lg,
                            right: HomeLayout.gutter),
                        child: Text(
                          '${items.length} ${'items'.tr}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: homeMutedColor(context)),
                        ),
                      ),
                    ),
                    // One row per show: cover, full two-line title, host
                    // and Subscribe. Tapping opens the show; the cover's
                    // play button starts the latest episode.
                    SliverPadding(
                      padding: const EdgeInsets.only(
                          top: RiffSpacing.xs, bottom: RiffSpacing.listEnd),
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
                    const SliverToBoxAdapter(
                        child: SizedBox(height: RiffSpacing.unit * 20)),
                ],
              );
            }
            return _browseView(controller);
          }),
        ),
      ],
    );
  }

  static final _searchBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(RiffRadii.pill),
    borderSide: BorderSide.none,
  );

  // Accent colours for the browse category chips.
  static const _categoryColors = PodcastCategoryPalette.tiles;

  /// Search-focus landing: first the "listeners of X also enjoy" discovery
  /// scrollwheels, then Apple-Podcasts category tiles, then featured
  /// suggestions.
  Widget _browseView(LibraryPodcastsController controller) {
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
              crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
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
        const SliverToBoxAdapter(child: SizedBox(height: RiffSpacing.listEnd)),
      ],
    );
  }

  /// Category tile: a solid colour block with the genre name.
  Widget _categoryChip(String genreId, String name, int i) {
    final color = _categoryColors[i % _categoryColors.length];
    final riff = RiffColors.of(context);
    return Material(
      color: Color.alphaBlend(riff.scrim.withOpacity(0.18), color),
      borderRadius: BorderRadius.circular(RiffRadii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (shouldPlayPodcastShowOnTap()) {
            final ok = await playFirstPodcastInGenre(genreId);
            if (ok) return;
          }
          Get.to(() => PodcastCategoryScreen(genreId: genreId, name: name));
        },
        onLongPress: () =>
            Get.to(() => PodcastCategoryScreen(genreId: genreId, name: name)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RiffSpacing.md),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: riff.onImage),
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
    const cardWidth = RiffComponentSizes.videoEpisodeWidth;
    const thumbHeight = cardWidth * 9 / 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(title, top: RiffSpacing.md),
        SizedBox(
          // Thumb + two-line title + one meta line.
          height: thumbHeight +
              RiffSpacing.sm +
              riffLineHeight(context, homeCardTitleStyle(context)) * 2 +
              RiffSpacing.xxs +
              riffLineHeight(context, homeCardSubtitleStyle(context)) +
              RiffSpacing.sm,
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
                  borderRadius: BorderRadius.circular(RiffRadii.sm),
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
                        borderRadius: BorderRadius.circular(RiffRadii.sm),
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
                                  errorWidget: (_, __, ___) => ColoredBox(
                                      color: theme
                                          .colorScheme.surfaceContainerLow),
                                  placeholder: (_, __) => ColoredBox(
                                      color: theme
                                          .colorScheme.surfaceContainerLow),
                                )
                              else
                                ColoredBox(
                                    color:
                                        theme.colorScheme.surfaceContainerLow),
                              if (clock.isNotEmpty)
                                Positioned(
                                  right: RiffSpacing.sm,
                                  bottom: RiffSpacing.sm,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: RiffSpacing.xs,
                                        vertical: RiffSpacing.xxs),
                                    decoration: BoxDecoration(
                                      color: RiffColors.of(context)
                                          .scrim
                                          .withOpacity(0.75),
                                      borderRadius:
                                          BorderRadius.circular(RiffRadii.xs),
                                    ),
                                    child: Text(
                                      clock,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: RiffColors.of(context)
                                                  .onImage),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: RiffSpacing.sm),
                      Text(
                        ep.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: homeCardTitleStyle(context),
                      ),
                      const SizedBox(height: RiffSpacing.xxs),
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
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: HomeLayout.sectionTop,
                right: HomeLayout.gutter),
            child: Text(
              kicker!.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: homeMutedColor(context)),
            ),
          ),
        HomeSectionHeader(title,
            top: kicker != null ? RiffSpacing.xxs : HomeLayout.sectionTop),
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

/// A podcast search result: cover, two-line title, host and Subscribe.
class _ShowResultRow extends StatelessWidget {
  const _ShowResultRow(
      {super.key, required this.show, required this.controller});
  final Playlist show;
  final LibraryPodcastsController controller;

  void _open() => Get.toNamed(ScreenNavigationSetup.playlistScreen,
      id: ScreenNavigationSetup.id, arguments: [show, show.playlistId, true]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: HomeLayout.gutter, vertical: RiffSpacing.sm),
            child: Row(
              children: [
                PodcastArt(
                    url: show.thumbnailUrl,
                    size: RiffComponentSizes.showRowArt),
                const SizedBox(width: RiffSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        show.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if ((show.description ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: RiffSpacing.xxs),
                        Text(
                          show.description!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: RiffSpacing.sm),
                Obx(() {
                  final subscribed = controller.libraryPodcasts
                      .any((p) => p.playlistId == show.playlistId);
                  // Quiet in a list: outline + to subscribe, accent check
                  // once subscribed (toggled on; the show page has the full
                  // Subscribe button).
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
                      size: RiffComponentSizes.headerIcon,
                      color: subscribed
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Full-width hairline between search results (§5.2).
        const RiffRowHairline(),
      ],
    );
  }
}
