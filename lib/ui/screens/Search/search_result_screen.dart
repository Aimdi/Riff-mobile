import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/offline_playback.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/screens/Library/library_search.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/song_list_tile.dart';
import '/services/search_recents.dart';
import '/ui/screens/Plugins/seeker_screen.dart';
import '/ui/screens/Settings/settings_screen_controller.dart';
import '../../navigator.dart';
import '../../theme/riff_spacing.dart';
import '../Home/home_layout.dart';
import '../Podcasts/podcast_empty_state.dart';
import '../../widgets/animated_screen_transition.dart';
import '../../widgets/shimmer_widgets/skeleton_fade.dart';
import '../../widgets/shimmer_widgets/song_list_shimmer.dart';
import '../../widgets/search_related_widgets.dart';
import '../../widgets/separate_tab_item_widget.dart';
import 'components/search_spelling_line.dart';
import 'search_result_screen_controller.dart';

class SearchResultScreen extends StatelessWidget {
  const SearchResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // One left registered by an earlier results page (searched for other
    // words) would show that search's results instead of this one's.
    final args = Get.arguments;
    if (Get.isRegistered<SearchResultScreenController>() &&
        args is String &&
        Get.find<SearchResultScreenController>().queryString.value != args) {
      Get.delete<SearchResultScreenController>(force: true);
    }
    final searchResScrController =
        Get.isRegistered<SearchResultScreenController>()
            ? Get.find<SearchResultScreenController>()
            : Get.put(SearchResultScreenController());
    final topPadding = context.isLandscape ? 50.0 : 80.0;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QueryBar(controller: searchResScrController),
            const SizedBox(height: 8),
            _FilterChips(controller: searchResScrController),
            const SizedBox(height: 4),
            Expanded(
              child: GetX<SearchResultScreenController>(
                builder: (controller) => AnimatedScreenTransition(
                  enabled: Get.find<SettingsScreenController>()
                      .isTransitionAnimationDisabled
                      .isFalse,
                  forward: controller.isTabTransitionReversed,
                  // The filters are a row: results move along it.
                  horizontalTransition: true,
                  child: KeyedSubtree(
                    key: ValueKey<int>(
                        controller.navigationRailCurrentIndex.toInt() * 8),
                    // What's opened from here is kept among recent searches.
                    child: SearchRecentsScope(
                      child:
                          Body(searchResScrController: searchResScrController),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back button and the query in a pill; tapping the pill goes back to the
/// search field to change it.
class _QueryBar extends StatelessWidget {
  const _QueryBar({required this.controller});
  final SearchResultScreenController controller;

  void _back() => Get.nestedKey(ScreenNavigationSetup.id)!.currentState!.pop();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: RiffSpacing.xxs, right: HomeLayout.gutter),
      child: Row(
        children: [
          IconButton(
            tooltip: 'back'.tr,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _back,
          ),
          Expanded(
            child: Material(
              color: homeTileColor(context),
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _back,
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.search_rounded, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Obx(() => Text(
                              controller.queryString.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                            )),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "All" plus one chip per result type (and Soulseek when installed).
class _FilterChips extends StatefulWidget {
  const _FilterChips({required this.controller});
  final SearchResultScreenController controller;

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  /// The result types' chips, arriving with the results, fade in.
  final _arriving = LoadedRowsFade();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Obx(() {
      final fetched = controller.isResultContentFetced.value;
      if (!fetched) _arriving.skeleton();
      final labels = [
        'allResults'.tr,
        if (fetched)
          ...controller.railItems
              .map((e) => e.toLowerCase().removeAllWhitespace.tr),
      ];
      final selected = controller.navigationRailCurrentIndex.value;
      final scheme = Theme.of(context).colorScheme;
      final idleFill = homeTileColor(context);
      final idleBorder = homeTileBorder(context);
      final labelStyle = Theme.of(context).textTheme.labelMedium;
      return SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: HomeLayout.gutter),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            // The picked chip's fill, outline and label ease over.
            final chip = TweenAnimationBuilder<double>(
              tween: Tween(end: i == selected ? 1 : 0),
              duration: RiffDurations.select,
              curve: RiffDurations.selectCurve,
              builder: (context, t, _) => Material(
                color: Color.lerp(idleFill, scheme.secondary, t),
                shape: StadiumBorder(
                    side: BorderSide.lerp(idleBorder, BorderSide.none, t)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => controller.onDestinationSelected(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: labelStyle?.copyWith(
                            color: Color.lerp(
                                scheme.onSurface, scheme.onPrimary, t)),
                      ),
                    ),
                  ),
                ),
              ),
            );
            // "All" is there from the start.
            if (i == 0) return chip;
            return _arriving.row(chip,
                key: ValueKey(controller.railItems[i - 1]));
          },
        ),
      );
    });
  }
}

class Body extends StatelessWidget {
  const Body({
    super.key,
    required this.searchResScrController,
  });

  final SearchResultScreenController searchResScrController;

  @override
  Widget build(BuildContext context) {
    if (searchResScrController.navigationRailCurrentIndex.value == 0) {
      // What the search found fades in where its skeleton was.
      return Obx(() => SkeletonFadeIn(
            skeleton: const SongListShimmer(itemCount: 8, topPadding: 12),
            child: searchResScrController.isResultContentFetced.isFalse
                ? null
                : _overview(),
          ));
    } else {
      if (searchResScrController.isResultContentFetced.isTrue) {
        final name = searchResScrController.railItems[
            searchResScrController.navigationRailCurrentIndex.value - 1];
        if (searchResScrController.isSoulseekRail(name)) {
          return SeekerScreen(
            embedded: true,
            initialQuery: searchResScrController.queryString.value,
          );
        }
        return SeparateTabItemWidget(
          items: const [],
          title: name,
          topPadding: 8,
          scrollController: searchResScrController.scrollControllers[name],
        );
      }
    }
    return const SizedBox.shrink();
  }

  /// The "All" results once the search is back: what it found, nothing
  /// found, or why it failed. Read inside the page's Obx.
  Widget _overview() {
    // The search failed (not "no match"): why, and try again.
    if (searchResScrController.searchFailed.isTrue) {
      final offline = OfflinePlayback.offline.value;
      final icon = offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded;
      final message = (offline ? 'searchOffline' : 'searchFailed').tr;
      // And what your library has for it, playable as it is.
      final mine = librarySearchMatches(
          searchResScrController.queryString.value, _librarySongs());
      if (mine.isNotEmpty) {
        return _LibraryMatches(
            icon: icon,
            message: message,
            songs: mine,
            onRetry: searchResScrController.retrySearch);
      }
      return PodcastEmptyState(
        icon: icon,
        message: message,
        actionLabel: 'retry'.tr,
        actionIcon: Icons.refresh_rounded,
        onAction: searchResScrController.retrySearch,
      );
    }
    // Soulseek-only rail still means YTM returned nothing — show empty
    // state on Results rather than a blank column.
    final ytmRails = searchResScrController.railItems
        .where((r) => !searchResScrController.isSoulseekRail(r))
        .toList();
    if (ytmRails.isEmpty) {
      final hasSoulseek = searchResScrController.railItems
          .any(searchResScrController.isSoulseekRail);
      final empty = PodcastEmptyState(
        icon: Icons.search_off_rounded,
        message:
            "${"nomatch".tr}\n'${searchResScrController.queryString.value}'",
        actionLabel: hasSoulseek ? 'soulseek'.tr : null,
        actionIcon: Icons.search_rounded,
        onAction: hasSoulseek
            ? () {
                final idx = searchResScrController.railItems
                    .indexWhere(searchResScrController.isSoulseekRail);
                if (idx >= 0) {
                  searchResScrController.onDestinationSelected(idx + 1);
                }
              }
            : null,
      );
      // Nothing for the words as typed: "Did you mean …" above.
      final spelling = searchResScrController.spelling;
      if (spelling == null) return empty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchSpellingLine(
            spelling: spelling,
            searched: searchResScrController.queryString.value,
            onCorrected: searchResScrController.searchCorrected,
            onOriginal: searchResScrController.searchOriginal,
          ),
          Expanded(child: empty),
        ],
      );
    }
    return const ResultWidget();
  }
}

/// Your library's songs: downloads and the song cache, and the phone's own
/// music files once listed. Read inside the page's Obx, so songs still
/// loading show up as they come.
List<MediaItem> _librarySongs() {
  if (!Get.isRegistered<LibrarySongsController>()) return const [];
  final library = Get.find<LibrarySongsController>();
  final listed = library.librarySongsList.toList();
  // Library › Songs searching: its list is narrowed, the whole kept aside.
  final all =
      library.tempListContainer.isNotEmpty ? library.tempListContainer : listed;
  return [...all, ...library.deviceSongs];
}

/// A search that couldn't reach YouTube Music, with what your library has
/// for it underneath, as Spotify's and YouTube Music's search finds your
/// downloads offline: a tap plays the song, the songs found as its queue.
class _LibraryMatches extends StatelessWidget {
  const _LibraryMatches({
    required this.icon,
    required this.message,
    required this.songs,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final List<MediaItem> songs;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: RiffSpacing.lg,
              top: RiffSpacing.md,
              right: RiffSpacing.sm,
              bottom: RiffSpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: RiffComponentSizes.trailingIcon, color: muted),
              const SizedBox(width: RiffSpacing.md),
              Expanded(
                child: Text(message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
              TextButton(onPressed: onRetry, child: Text('retry'.tr)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
              left: RiffSpacing.lg,
              top: RiffSpacing.sm,
              right: RiffSpacing.lg,
              bottom: RiffSpacing.xs),
          child:
              Text('fromYourLibrary'.tr, style: homeSectionTitleStyle(context)),
        ),
        for (var i = 0; i < songs.length; i++)
          SongListTile(
            key: ValueKey(songs[i].id),
            song: songs[i],
            onTap: () => Get.find<PlayerController>().playPlayListSong(songs, i,
                playfrom: PlaylingFrom(
                    type: PlaylingFromType.SELECTION,
                    name: 'fromYourLibrary'.tr)),
          ),
      ],
    );
  }
}
