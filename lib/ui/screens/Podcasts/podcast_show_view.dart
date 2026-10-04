import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_playback_profile.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'podcast_library_ui.dart';
import 'podcast_playback_controls.dart';

import '/services/podcast_progress_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/widgets/podcast_follow_button.dart';
import '../Home/home_layout.dart';
import 'podcast_layout.dart';

/// "1 episode" / "12 episodes".
String podcastEpisodeCount(int n) =>
    n == 1 ? 'episodeCountOne'.tr : 'episodeCount'.trParams({'count': '$n'});

/// Plain text from feed HTML (show notes), for two-line previews.
String podcastPlainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

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
  bool _oldestFirst = false;

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
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eps = widget.episodes;
    final order = List<int>.generate(eps.length, (i) => i);
    if (_oldestFirst) order.setAll(0, order.reversed.toList());
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
                      : '${'showEpisodes'.tr} · ${eps.length}',
                  trailing: eps.length < 2
                      ? null
                      : TextButton.icon(
                          onPressed: () =>
                              setState(() => _oldestFirst = !_oldestFirst),
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
                            _oldestFirst ? 'oldestFirst'.tr : 'newestFirst'.tr,
                          ),
                        ),
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
              else if (eps.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(RiffSpacing.x3l),
                    child: Center(
                      child: Text('noEpisodes'.tr,
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
                      return _EpisodeRow(
                        key: ValueKey(eps[index].id),
                        episode: eps[index],
                        onTap: () => widget.onPlay(index),
                        onLongPress: widget.onEpisodeLongPress == null
                            ? null
                            : () => widget.onEpisodeLongPress!(eps[index]),
                        divider: i < eps.length - 1,
                      );
                    },
                    childCount: eps.length,
                  ),
                ),
              if (widget.footer != null)
                SliverToBoxAdapter(child: widget.footer!),
              const SliverToBoxAdapter(
                  child: SizedBox(height: RiffSpacing.listEnd)),
            ],
          ),
          _topBar(context, theme),
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
                  PodcastPlaybackPrefs.hasShowOverride(widget.playbackKey);
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
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, child: Text('showLibrarySettings'.tr)),
                if (widget.episodes.isNotEmpty)
                  PopupMenuItem(value: 1, child: Text('markAllListened'.tr)),
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
                            : () => widget.onPlay(resume ?? 0),
                        icon: const Icon(Icons.play_arrow_rounded,
                            size: RiffComponentSizes.headerIcon),
                        label: Text(
                          resume != null
                              ? 'resumeEpisode'.tr
                              : 'latestEpisode'.tr,
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
    final text = podcastPlainText(widget.description);
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
            Text(
              text,
              maxLines: _aboutOpen ? null : 3,
              overflow:
                  _aboutOpen ? TextOverflow.visible : TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: homeMutedColor(context)),
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
  });

  final MediaItem episode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool divider;

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
    final meta = episodeMetaLine(['${episode.extras?['date'] ?? ''}', length]);
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
                  playing
                      ? SizedBox.square(
                          dimension: kMinInteractiveDimension,
                          child: Icon(Icons.graphic_eq_rounded,
                              color: accent,
                              size: RiffComponentSizes.headerIcon),
                        )
                      : PodcastPlayButton(onPressed: onTap),
                ],
              ),
            ),
          ),
        );
    return Column(
      children: [
        player == null
            ? body(false)
            : Obx(() => body(player.currentSong.value?.id == episode.id)),
        // Full-width hairline between episodes (§5.2).
        if (divider) const Divider(height: 1),
      ],
    );
  }
}
