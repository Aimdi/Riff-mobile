import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/podcast_playback_profile.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'podcast_library_ui.dart';
import 'podcast_playback_controls.dart';

import '/models/thumbnail.dart';
import '/services/podcast_progress_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/utils/theme_controller.dart';
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
                            foregroundColor: homeMutedColor(context),
                            textStyle: theme.textTheme.labelMedium,
                            minimumSize: const Size(0, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: const Icon(Icons.swap_vert_rounded, size: 18),
                          label: Text(
                            _oldestFirst ? 'oldestFirst'.tr : 'newestFirst'.tr,
                          ),
                        ),
                ),
              ),
              if (widget.loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                )
              else if (eps.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
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
              const SliverToBoxAdapter(child: SizedBox(height: 200)),
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
      duration: const Duration(milliseconds: 180),
      color: _showTitle ? theme.scaffoldBackgroundColor : Colors.transparent,
      padding: EdgeInsets.only(top: top + 4, left: 4, right: 12, bottom: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'back'.tr,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: AnimatedOpacity(
              opacity: _showTitle ? 1 : 0,
              duration: const Duration(milliseconds: 180),
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
                    size: 22,
                    color: custom ? theme.colorScheme.secondary : null),
                onPressed: () => showPodcastShowPlaybackSheet(context,
                    showKey: widget.playbackKey!, title: widget.title),
              );
            }),
          if (widget.playbackKey != null)
            PopupMenuButton<int>(
              tooltip: 'moreOptions'.tr,
              icon: const Icon(Icons.more_vert_rounded, size: 22),
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
    final cover = (width * 0.5).clamp(160.0, 240.0);
    final eps = widget.episodes;
    final resume = widget.loading ? null : _resumeIndex();
    final latestDate = eps.isEmpty ? '' : '${eps.first.extras?['date'] ?? ''}';
    final meta = episodeMetaLine([
      if (!widget.loading && eps.isNotEmpty) podcastEpisodeCount(eps.length),
      latestDate,
    ]);
    return Stack(
      children: [
        // Soft wash of the cover behind the header.
        Positioned.fill(
          child: widget.artUrl.isEmpty
              ? const SizedBox.shrink()
              : ShaderMask(
                  shaderCallback: (r) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      RiffColors.of(context).scrim.withOpacity(0.55),
                      Colors.transparent
                    ],
                  ).createShader(r),
                  blendMode: BlendMode.dstIn,
                  child: Opacity(
                    opacity: 0.45,
                    child: CachedNetworkImage(
                      imageUrl: Thumbnail(widget.artUrl).medium,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      color: RiffColors.of(context).scrim.withOpacity(0.35),
                      colorBlendMode: BlendMode.darken,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: EdgeInsets.only(
              left: HomeLayout.gutter + RiffSpacing.sm,
              top: top + RiffSpacing.unit * 16,
              right: HomeLayout.gutter + RiffSpacing.sm,
              bottom: RiffSpacing.xs),
          child: Column(
            children: [
              Container(
                width: cover,
                height: cover,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: RiffColors.of(context).scrim.withOpacity(0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: PodcastArt(url: widget.artUrl, size: cover),
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (widget.author.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.author,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.secondary),
                ),
              ],
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(meta,
                    textAlign: TextAlign.center,
                    style: homeCardSubtitleStyle(context)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: RiffSurfaces.voidBlack,
                          textStyle: theme.textTheme.labelLarge,
                          disabledBackgroundColor:
                              theme.colorScheme.secondary.withOpacity(0.35),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: eps.isEmpty
                            ? null
                            : () => widget.onPlay(resume ?? 0),
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: Text(
                          resume != null
                              ? 'resumeEpisode'.tr
                              : 'latestEpisode'.tr,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
        borderRadius: BorderRadius.circular(8),
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
            const SizedBox(height: 4),
            Text(
              _aboutOpen ? 'showLess'.tr : 'readMore'.tr,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).textTheme.titleMedium?.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// One episode: date · length, two-line title, a two-line preview of the
/// notes, progress when partly played, and a play button.
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
    final accent = theme.colorScheme.secondary;
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
    Widget body(bool playing) => InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.only(
                left: HomeLayout.gutter,
                top: RiffSpacing.lg,
                right: HomeLayout.gutter - RiffSpacing.xs,
                bottom: RiffSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (meta.isNotEmpty)
                        Text(meta,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: homeMutedColor(context))),
                      const SizedBox(height: 3),
                      Text(
                        episode.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: playing ? accent : null),
                      ),
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          notes,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: homeMutedColor(context)),
                        ),
                      ],
                      if (partly) ...[
                        const SizedBox(height: 8),
                        FractionallySizedBox(
                          widthFactor: 0.45,
                          alignment: Alignment.centerLeft,
                          child: PodcastProgressBar(value: prog),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                playing
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.graphic_eq_rounded,
                            color: accent, size: 26),
                      )
                    : PodcastPlayButton(onPressed: onTap),
              ],
            ),
          ),
        );
    return Column(
      children: [
        player == null
            ? body(false)
            : Obx(() => body(player.currentSong.value?.id == episode.id)),
        if (divider)
          Divider(
            height: 1,
            indent: HomeLayout.gutter,
            endIndent: HomeLayout.gutter,
            color: theme.dividerColor.withOpacity(0.25),
          ),
      ],
    );
  }
}
