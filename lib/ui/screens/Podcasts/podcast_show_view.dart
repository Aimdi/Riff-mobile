import 'package:audio_service/audio_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/podcast_playback_profile.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'podcast_library_ui.dart';
import 'podcast_playback_controls.dart';

import '/services/podcast_download_service.dart';
import '/services/podcast_progress_service.dart';
import '/services/podcast_share.dart';
import '/services/podcast_show_view_prefs.dart';
import '/services/show_notes_links.dart';
import '/ui/player/components/show_notes_text.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Audiobooks/audiobook_widgets.dart'
    show AudiobookSearchField;
import '/ui/widgets/podcast_follow_button.dart';
import '/ui/widgets/now_playing_bars.dart';
import '/ui/widgets/riff_sheet.dart';
import '/ui/widgets/snackbar.dart';
import '../Home/home_layout.dart';
import 'podcast_layout.dart';
import 'podcast_queue_controller.dart';

/// "1 episode" / "12 episodes".
String podcastEpisodeCount(int n) =>
    n == 1 ? 'episodeCountOne'.tr : 'episodeCount'.trParams({'count': '$n'});

/// Plain text from feed HTML (show notes), for two-line previews: links
/// down to their words.
String podcastPlainText(String html) => showNotesWithoutAddresses(html)
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whether [episode] has [query] in its title or notes (any case), for
/// searching a show's episodes.
bool podcastEpisodeMatches(MediaItem episode, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return episode.title.toLowerCase().contains(q) ||
      podcastPlainText('${episode.extras?['description'] ?? ''}')
          .toLowerCase()
          .contains(q);
}

/// A podcast's page, shared by RSS (Apple) shows and YouTube Music / YouTube
/// podcasts: big cover, title and host, Play latest / Resume and
/// Subscribe, About, then the episode list (newest or oldest first).
class PodcastShowView extends StatefulWidget {
  const PodcastShowView({
    super.key,
    required this.title,
    required this.author,
    required this.artUrl,
    required this.description,
    required this.episodes,
    required this.loading,
    required this.subscribed,
    required this.onToggleSubscribe,
    required this.onPlay,
    this.onEpisodeLongPress,
    this.onBack,
    this.footer,
    this.playbackKey,
  });

  final String title;
  final String author;
  final String artUrl;
  final String description;

  /// Episodes in feed order (newest first).
  final List<MediaItem> episodes;
  final bool loading;
  final bool subscribed;
  final VoidCallback onToggleSubscribe;

  /// Plays [episodes] starting at this index (feed order).
  final void Function(int index) onPlay;
  final void Function(MediaItem episode)? onEpisodeLongPress;
  final VoidCallback? onBack;
  final Widget? footer;

  /// Key this show's playback settings are stored under (feed URL or
  /// `yt:<playlist>`); null hides the Playback settings button.
  final String? playbackKey;

  @override
  State<PodcastShowView> createState() => _PodcastShowViewState();
}

class _PodcastShowViewState extends State<PodcastShowView> {
  final _scroll = ScrollController();
  bool _showTitle = false;
  bool _aboutOpen = false;

  /// Kept per show (by [PodcastShowView.playbackKey]), as Pocket Casts does;
  /// a serial show (its feed says it's heard in order) lists oldest first
  /// until set otherwise, as in Apple Podcasts. [_orderPick] is the order
  /// picked here, for shows with no key to keep it under.
  bool? _orderPick;
  bool get _oldestFirst =>
      _orderPick ??
      PodcastShowViewPrefs.oldestFirst(widget.playbackKey,
          serial: widget.episodes.firstOrNull?.extras?['serial'] == true);
  late bool _hidePlayed = PodcastShowViewPrefs.hidePlayed(widget.playbackKey);

  void _toggleOrder() {
    final oldestFirst = !_oldestFirst;
    setState(() => _orderPick = oldestFirst);
    final show = widget.playbackKey;
    if (show != null) PodcastShowViewPrefs.setOldestFirst(show, oldestFirst);
  }

  void _toggleHidePlayed() {
    setState(() => _hidePlayed = !_hidePlayed);
    final show = widget.playbackKey;
    if (show != null) PodcastShowViewPrefs.setHidePlayed(show, _hidePlayed);
  }

  /// Searching the episodes (Pocket Casts, AntennaPod): the field under the
  /// header filters them as you type.
  bool _searching = false;
  late final _search = TextEditingController()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) _search.clear();
  }

  /// Selecting episodes, as in Pocket Casts and AntennaPod: the ids picked
  /// (null when not selecting), to queue, download or mark played at once.
  Set<String>? _selected;

  void _startSelecting() => setState(() => _selected = <String>{});

  void _stopSelecting() => setState(() => _selected = null);

  void _togglePicked(String id) => setState(() {
        final picked = _selected;
        if (picked == null) return;
        if (!picked.remove(id)) picked.add(id);
      });

  /// All of [shown] picked, or none when they all are.
  void _pickAll(List<MediaItem> shown) => setState(() {
        final picked = _selected;
        if (picked == null) return;
        final all = shown.every((e) => picked.contains(e.id));
        all ? picked.clear() : picked.addAll(shown.map((e) => e.id));
      });

  /// [at] and every episode [shown] above it, or under it with [below],
  /// picked as well (none unpicked).
  void _pickRange(List<MediaItem> shown, int at, {required bool below}) =>
      setState(() {
        final picked = _selected;
        if (picked == null || at < 0 || at >= shown.length) return;
        final range = below ? shown.sublist(at) : shown.sublist(0, at + 1);
        picked.addAll(range.map((e) => e.id));
      });

  /// A long press while selecting, as in AntennaPod and Pocket Casts: this
  /// episode and all above it, or all below it, picked at once (catching
  /// up on a show: everything older, then Mark as played).
  void _pickRangeSheet(List<MediaItem> shown, int at) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: RiffSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RiffSheetHandle(),
              RiffSheetTile(
                icon: Icons.vertical_align_top_rounded,
                title: 'selectAllAbove'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  _pickRange(shown, at, below: false);
                },
              ),
              RiffSheetTile(
                icon: Icons.vertical_align_bottom_rounded,
                title: 'selectAllBelow'.tr,
                onTap: () {
                  Navigator.of(sheet).pop();
                  _pickRange(shown, at, below: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The episodes picked, in the feed's order.
  List<MediaItem> get _picked => [
        for (final e in widget.episodes)
          if (_selected?.contains(e.id) ?? false) e
      ];

  void _snack(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(themedSnackbar(Theme.of(context), text));
  }

  void _queuePicked() {
    if (!Get.isRegistered<PodcastQueueController>()) return;
    final queue = Get.find<PodcastQueueController>();
    final adding = _picked.where((e) => !queue.isQueued(e.id)).toList();
    adding.forEach(queue.add);
    _stopSelecting();
    _snack('addedNToQueue'.trParams({'count': '${adding.length}'}));
  }

  void _downloadPicked() {
    final todo = _picked
        .where((e) =>
            !PodcastDownloadService.isDownloaded(e.id) &&
            '${e.extras?['url'] ?? ''}'.isNotEmpty)
        .toList();
    _stopSelecting();
    if (todo.isEmpty) return _snack('nothingToDownload'.tr);
    _snack('downloadingEpisodes'.trParams({'count': '${todo.length}'}));
    // One after the other, as a show's new episodes download.
    unawaited(() async {
      for (final episode in todo) {
        await PodcastDownloadService.download(episode);
      }
    }());
  }

  void _markPickedPlayed() {
    final picked = _picked;
    _stopSelecting();
    markShowListened(context, picked, onChanged: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 260;
      if (show != _showTitle) setState(() => _showTitle = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Listed oldest first, a series plays in order: the index (feed order)
  /// of its first episode not yet played, else of its first.
  int _nextInOrder() {
    final eps = widget.episodes;
    for (var i = eps.length - 1; i >= 0; i--) {
      if (!PodcastProgressService.isPlayed(eps[i].id)) return i;
    }
    return eps.length - 1;
  }

  /// Index (feed order) of this show's episode with a saved position.
  int? _resumeIndex() {
    final ids = {
      for (var i = 0; i < widget.episodes.length; i++) widget.episodes[i].id: i
    };
    for (final r in PodcastProgressService.inProgress()) {
      final i = ids['${r['id']}'];
      if (i != null) return i;
    }
    return null;
  }

  /// Episodes marked played (or resumed) change the list while it's open.
  late final ValueListenable<Box>? _played = Hive.isBoxOpen('PodcastPlayed')
      ? Hive.box('PodcastPlayed').listenable()
      : null;

  @override
  Widget build(BuildContext context) {
    final played = _played;
    if (played == null) return _page(context);
    return ValueListenableBuilder<Box>(
      valueListenable: played,
      builder: (context, _, __) => _page(context),
    );
  }

  Widget _page(BuildContext context) {
    final theme = Theme.of(context);
    final eps = widget.episodes;
    final query = _searching ? _search.text.trim() : '';
    final order = showEpisodeOrder(eps.length,
        oldestFirst: _oldestFirst,
        hidden: _hidePlayed || query.isNotEmpty
            ? (i) =>
                (_hidePlayed && PodcastProgressService.isPlayed(eps[i].id)) ||
                !podcastEpisodeMatches(eps[i], query)
            : null);
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (widget.description.trim().isNotEmpty)
                SliverToBoxAdapter(child: _about(context)),
              SliverToBoxAdapter(
                child: HomeSectionHeader(
                  widget.loading
                      ? 'showEpisodes'.tr
                      : '${'showEpisodes'.tr} · ${order.length}',
                  trailing: eps.length < 2
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'searchEpisodes'.tr,
                              isSelected: _searching,
                              onPressed: _toggleSearch,
                              style: IconButton.styleFrom(
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: RiffSpacing.sm,
                                    vertical: RiffSpacing.xs),
                              ),
                              icon: const Icon(Icons.search_rounded,
                                  size: RiffComponentSizes.trailingIcon),
                              selectedIcon: Icon(Icons.search_rounded,
                                  size: RiffComponentSizes.trailingIcon,
                                  color: theme.colorScheme.primary),
                            ),
                            // Played episodes out of the way (on: accent).
                            IconButton(
                              tooltip: (_hidePlayed
                                      ? 'showPlayedEpisodes'
                                      : 'hidePlayedEpisodes')
                                  .tr,
                              isSelected: _hidePlayed,
                              onPressed: _toggleHidePlayed,
                              // As compact as the sort button beside it.
                              style: IconButton.styleFrom(
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: RiffSpacing.sm,
                                    vertical: RiffSpacing.xs),
                              ),
                              icon: const Icon(Icons.visibility_rounded,
                                  size: RiffComponentSizes.trailingIcon),
                              selectedIcon: Icon(Icons.visibility_off_rounded,
                                  size: RiffComponentSizes.trailingIcon,
                                  color: theme.colorScheme.primary),
                            ),
                            TextButton.icon(
                              onPressed: _toggleOrder,
                              style: TextButton.styleFrom(
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: RiffSpacing.md,
                                    vertical: RiffSpacing.xs),
                              ),
                              icon: const Icon(Icons.swap_vert_rounded,
                                  size: RiffComponentSizes.trailingIcon),
                              label: Text(
                                _oldestFirst
                                    ? 'oldestFirst'.tr
                                    : 'newestFirst'.tr,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (_searching)
                SliverToBoxAdapter(
                  child: AudiobookSearchField(
                    controller: _search,
                    hint: 'searchEpisodes'.tr,
                    autofocus: true,
                    onSubmitted: (_) {},
                    onClear: _toggleSearch,
                  ),
                ),
              if (widget.loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(RiffSpacing.unit * 10),
                    child: Center(
                      child: SizedBox.square(
                        dimension: RiffComponentSizes.spinner,
                        child: CircularProgressIndicator(
                            strokeWidth: RiffComponentSizes.spinnerStroke),
                      ),
                    ),
                  ),
                )
              else if (order.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(RiffSpacing.x3l),
                    child: Center(
                      child: Text(
                          eps.isEmpty
                              ? 'noEpisodes'.tr
                              : query.isNotEmpty
                                  ? 'noEpisodesMatch'.tr
                                  : 'allEpisodesPlayed'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: homeMutedColor(context))),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final index = order[i];
                      final picked = _selected;
                      return _EpisodeRow(
                        key: ValueKey(eps[index].id),
                        episode: eps[index],
                        selected: picked?.contains(eps[index].id),
                        onTap: picked != null
                            ? () => _togglePicked(eps[index].id)
                            : () => widget.onPlay(index),
                        onLongPress: picked != null
                            ? () => _pickRangeSheet(
                                [for (final j in order) eps[j]], i)
                            : widget.onEpisodeLongPress == null
                                ? null
                                : () => widget.onEpisodeLongPress!(eps[index]),
                        divider: i < order.length - 1,
                      );
                    },
                    childCount: order.length,
                  ),
                ),
              if (widget.footer != null)
                SliverToBoxAdapter(child: widget.footer!),
              const SliverToBoxAdapter(
                  child: SizedBox(height: RiffSpacing.listEnd)),
            ],
          ),
          _selected == null
              ? _topBar(context, theme)
              : _selectionBar(context, theme, [for (final i in order) eps[i]]),
        ],
      ),
    );
  }

  /// The top bar while selecting: how many are picked, and what to do
  /// with them.
  Widget _selectionBar(
      BuildContext context, ThemeData theme, List<MediaItem> shown) {
    final count = _selected?.length ?? 0;
    Widget action(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip.tr,
          icon: Icon(icon, size: RiffComponentSizes.headerIcon),
          onPressed: count == 0 ? null : onPressed,
        );
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + RiffSpacing.xs,
          left: RiffSpacing.xs,
          right: RiffSpacing.md,
          bottom: RiffSpacing.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'cancel'.tr,
            icon: const Icon(Icons.close_rounded,
                size: RiffComponentSizes.trailingIcon),
            onPressed: _stopSelecting,
          ),
          Expanded(
            child: Text(
              'selectedCount'.trParams({'count': '$count'}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'selectAll'.tr,
            icon: const Icon(Icons.select_all_rounded,
                size: RiffComponentSizes.headerIcon),
            onPressed: shown.isEmpty ? null : () => _pickAll(shown),
          ),
          action('addToQueue', Icons.playlist_add_rounded, _queuePicked),
          action('download', Icons.download_outlined, _downloadPicked),
          action('markAsPlayed', Icons.check_circle_outline_rounded,
              _markPickedPlayed),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, ThemeData theme) {
    final top = MediaQuery.paddingOf(context).top;
    return AnimatedContainer(
      duration: RiffDurations.select,
      color: _showTitle ? theme.scaffoldBackgroundColor : Colors.transparent,
      padding: EdgeInsets.only(
          top: top + RiffSpacing.xs,
          left: RiffSpacing.xs,
          right: RiffSpacing.md,
          bottom: RiffSpacing.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'back'.tr,
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: RiffComponentSizes.trailingIcon),
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: AnimatedOpacity(
              opacity: _showTitle ? 1 : 0,
              duration: RiffDurations.select,
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          if (widget.playbackKey != null)
            Obx(() {
              PodcastPlaybackPrefs.rev.value;
              final custom =
                  PodcastPlaybackPrefs.hasShowOverride(widget.playbackKey) ||
                      PodcastPlaybackPrefs.showTrim(widget.playbackKey).isOn;
              return IconButton(
                tooltip: 'playbackSettings'.tr,
                icon: Icon(Icons.tune_rounded,
                    size: RiffComponentSizes.headerIcon,
                    color: custom ? theme.colorScheme.primary : null),
                onPressed: () => showPodcastShowPlaybackSheet(context,
                    showKey: widget.playbackKey!, title: widget.title),
              );
            }),
          if (widget.playbackKey != null)
            PopupMenuButton<int>(
              tooltip: 'moreOptions'.tr,
              icon: const Icon(Icons.more_vert_rounded,
                  size: RiffComponentSizes.headerIcon),
              onSelected: (v) {
                switch (v) {
                  case 0:
                    showPodcastShowLibrarySheet(context,
                        showKey: widget.playbackKey!, title: widget.title);
                  case 1:
                    markShowListened(context, widget.episodes, onChanged: () {
                      if (mounted) setState(() {});
                    });
                  case 2:
                    _startSelecting();
                  case 3:
                    Share.share(
                        podcastShowShareText(widget.title, widget.playbackKey));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, child: Text('showLibrarySettings'.tr)),
                if (widget.episodes.isNotEmpty)
                  PopupMenuItem(value: 1, child: Text('markAllListened'.tr)),
                if (widget.episodes.length > 1)
                  PopupMenuItem(value: 2, child: Text('selectEpisodes'.tr)),
                // As Pocket Casts, Apple Podcasts and Spotify share a show.
                if (podcastShowShareLink(widget.playbackKey) != null)
                  PopupMenuItem(value: 3, child: Text('shareShow'.tr)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    final cover = (width * 0.5).clamp(
        RiffComponentSizes.showCoverMin, RiffComponentSizes.showCoverMax);
    final eps = widget.episodes;
    final resume = widget.loading ? null : _resumeIndex();
    // Listed oldest first: the series' next episode, not its latest.
    final inOrder = resume == null && eps.isNotEmpty && _oldestFirst
        ? _nextInOrder()
        : null;
    final latestDate = eps.isEmpty ? '' : '${eps.first.extras?['date'] ?? ''}';
    final meta = episodeMetaLine([
      if (!widget.loading && eps.isNotEmpty) podcastEpisodeCount(eps.length),
      latestDate,
    ]);
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
              left: HomeLayout.gutter + RiffSpacing.sm,
              top: top + RiffSpacing.unit * 16,
              right: HomeLayout.gutter + RiffSpacing.sm,
              bottom: RiffSpacing.xs),
          child: Column(
            children: [
              // Flat cover, radius 8, no shadow.
              SizedBox(
                width: cover,
                height: cover,
                child: PodcastArt(url: widget.artUrl, size: cover),
              ),
              const SizedBox(height: RiffSpacing.lg),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
              if (widget.author.trim().isNotEmpty) ...[
                const SizedBox(height: RiffSpacing.xs),
                Text(
                  widget.author,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: RiffSpacing.xs),
                Text(meta,
                    textAlign: TextAlign.center,
                    style: homeCardSubtitleStyle(context)),
              ],
              const SizedBox(height: RiffSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: RiffComponentSizes.button,
                      // Primary pill from the theme (§5.5).
                      child: FilledButton.icon(
                        onPressed: eps.isEmpty
                            ? null
                            : () => widget.onPlay(resume ?? inOrder ?? 0),
                        icon: const Icon(Icons.play_arrow_rounded,
                            size: RiffComponentSizes.headerIcon),
                        label: Text(
                          resume != null
                              ? 'resumeEpisode'.tr
                              : inOrder == null
                                  ? 'latestEpisode'.tr
                                  : inOrder == eps.length - 1
                                      ? 'firstEpisode'.tr
                                      : 'nextEpisode'.tr,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: RiffSpacing.md),
                  PodcastFollowButton(
                    following: widget.subscribed,
                    onPressed: widget.onToggleSubscribe,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _about(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: homeMutedColor(context));
    return Padding(
      padding: const EdgeInsets.only(
          left: HomeLayout.gutter,
          top: RiffSpacing.lg,
          right: HomeLayout.gutter),
      child: InkWell(
        borderRadius: BorderRadius.circular(RiffRadii.sm),
        onTap: () => setState(() => _aboutOpen = !_aboutOpen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Open: as the show wrote it, paragraphs and links that open
            // (its support links last); closed, three lines of it.
            if (_aboutOpen)
              ShowNotesText(
                notes: widget.description.trim(),
                style: style,
                onLink: (url) => launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication),
              )
            else
              Text(
                podcastPlainText(widget.description),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            const SizedBox(height: RiffSpacing.xs),
            // A link: accent (§2.5).
            Text(
              _aboutOpen ? 'showLess'.tr : 'readMore'.tr,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// One episode: date · length, two-line title, a three-line preview of the
/// notes, progress when partly played, and a play pill. Now playing: accent
/// title and equalizer on an accentMuted tint.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.episode,
    required this.onTap,
    this.onLongPress,
    this.divider = true,
    this.selected,
  });

  final MediaItem episode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool divider;

  /// While episodes are being selected, whether this one is (a tap picks
  /// it or lets it go); null otherwise.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;
    final muted = scheme.onSurfaceVariant;
    final tot = episode.duration?.inSeconds ?? 0;
    final prog = PodcastProgressService.progress(episode.id);
    final left = PodcastProgressService.remainingSec(episode.id,
        fallbackDurationSec: tot);
    final partly = prog != null && prog > 0.01 && prog < 0.98;
    final length = partly && left != null && left > 0
        ? '${compactEpisodeLength(left)} ${'left'.tr}'
        : compactEpisodeLength(tot);
    final meta = episodeMetaLine([
      episodeNumberLabel(episode),
      '${episode.extras?['date'] ?? ''}',
      length,
    ]);
    final notes = podcastPlainText('${episode.extras?['description'] ?? ''}');
    final player = Get.isRegistered<PlayerController>()
        ? Get.find<PlayerController>()
        : null;
    Widget body(bool playing) => Material(
          color:
              playing ? RiffColors.of(context).accentMuted : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.only(
                  left: HomeLayout.gutter,
                  top: RiffSpacing.md,
                  right: HomeLayout.gutter - RiffSpacing.xs,
                  bottom: RiffSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (meta.isNotEmpty)
                          Text(meta,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: muted)),
                        const SizedBox(height: RiffSpacing.xxs),
                        Text(
                          episode.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(color: playing ? accent : null),
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: RiffSpacing.xs),
                          Text(
                            notes,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: muted),
                          ),
                        ],
                        if (partly) ...[
                          const SizedBox(height: RiffSpacing.sm),
                          FractionallySizedBox(
                            widthFactor: 0.45,
                            alignment: Alignment.centerLeft,
                            child: PodcastProgressBar(value: prog),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: RiffSpacing.sm),
                  if (selected != null)
                    SizedBox.square(
                      dimension: kMinInteractiveDimension,
                      child: Center(
                        child: Icon(
                          selected!
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: RiffComponentSizes.headerIcon,
                          color: selected! ? accent : muted,
                        ),
                      ),
                    )
                  else if (playing)
                    const SizedBox.square(
                      dimension: kMinInteractiveDimension,
                      child: Center(
                          child: NowPlayingBars(
                              size: RiffComponentSizes.headerIcon)),
                    )
                  else
                    PodcastPlayButton(onPressed: onTap),
                ],
              ),
            ),
          ),
        );
    return Column(
      children: [
        // Picked or not, for screen readers, while selecting.
        Semantics(
          selected: selected,
          child: player == null
              ? body(false)
              : Obx(() => body(player.currentSong.value?.id == episode.id)),
        ),
        // Full-width hairline between episodes (§5.2).
        if (divider) const Divider(height: 1),
      ],
    );
  }
}
