import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '/services/podcast_bookmarks.dart';
import '/services/podcast_segments.dart';
import '/services/podcast_service.dart';
import '/services/podcast_transcripts.dart';
import '/ui/screens/Home/home_layout.dart';
import '/ui/screens/Podcasts/podcast_bookmarks_ui.dart';
import '/ui/widgets/riff_sheet.dart';
import '../player_controller.dart';

/// Episode transcript (feed `<podcast:transcript>` or YouTube captions).
/// The current line follows playback; tap a line to jump there, long-press
/// to bookmark it. Search, a spoiler blur for what's ahead, and segment
/// spans (sponsor, intro…) shaded in their seek-bar colours. Untimed
/// transcripts read as plain paragraphs.
class PodcastTranscriptSheet extends StatefulWidget {
  const PodcastTranscriptSheet({super.key, required this.item});
  final MediaItem item;

  static void open(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: riffSheetShape,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        // Own messenger so the bookmark confirmation shows on the sheet.
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: PodcastTranscriptSheet(item: item),
          ),
        ),
      ),
    );
  }

  @override
  State<PodcastTranscriptSheet> createState() => _PodcastTranscriptSheetState();
}

/// Index of the last cue starting at/before [posSec] (-1 before the first).
/// [hint] (the previous result) makes the common "same cue" case O(1).
int transcriptActiveIndex(List<PodcastTranscriptCue> cues, double posSec,
    {int hint = -1}) {
  if (hint >= 0 &&
      hint < cues.length &&
      cues[hint].startSec <= posSec &&
      (hint + 1 == cues.length || cues[hint + 1].startSec > posSec)) {
    return hint;
  }
  var active = -1;
  for (var i = 0; i < cues.length; i++) {
    if (cues[i].startSec <= posSec) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}

const _spoilerKey = 'podcastTranscriptSpoiler';

class _PodcastTranscriptSheetState extends State<PodcastTranscriptSheet> {
  late final Future<LoadedTranscript> _future;
  final _scroll = ItemScrollController();
  final _player = Get.find<PlayerController>();

  /// Auto-scroll follows playback until the user scrolls by hand.
  bool _follow = true;
  int _lastAutoScrolled = -1;

  /// Active cue, updated from the progress tick but only notifying when the
  /// cue changes, so only the affected rows rebuild.
  final _active = ValueNotifier<int>(-1);
  List<PodcastTranscriptCue> _cues = const [];
  Worker? _progressWorker;

  bool _searching = false;
  final _searchCtrl = TextEditingController();
  List<int> _matches = const [];
  int _matchIdx = -1;

  bool _spoiler = false;

  bool get _isCurrent => _player.currentSong.value?.id == widget.item.id;

  @override
  void initState() {
    super.initState();
    _spoiler = _prefs?.get(_spoilerKey) == true;
    _future = PodcastTranscriptService.load(widget.item);
    _future.then((t) {
      if (!mounted) return;
      _cues = t.timed ? t.cues : const [];
      _updateActive();
    });
    _progressWorker = ever(_player.progressBarStatus, (_) => _updateActive());
    _active.addListener(_maybeFollow);
  }

  @override
  void dispose() {
    _progressWorker?.dispose();
    _active.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Box? get _prefs => Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  void _updateActive() {
    if (_cues.isEmpty || !_isCurrent) return;
    final posSec =
        _player.progressBarStatus.value.current.inMilliseconds / 1000.0;
    _active.value = transcriptActiveIndex(_cues, posSec, hint: _active.value);
  }

  void _maybeFollow() {
    final active = _active.value;
    if (_follow && active >= 0 && active != _lastAutoScrolled) {
      _lastAutoScrolled = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _follow) _scrollTo(active);
      });
    }
  }

  void _scrollTo(int index) {
    if (!_scroll.isAttached) return;
    _scroll.scrollTo(
      index: index < 0 ? 0 : index,
      alignment: 0.35,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _resync() {
    setState(() => _follow = true);
    _lastAutoScrolled = -1;
    _maybeFollow();
  }

  void _seekTo(int i) {
    final cue = _cues[i];
    _player.seek(Duration(milliseconds: (cue.startSec * 1000).round()));
    _resync();
    _scrollTo(i);
  }

  Future<void> _bookmark(BuildContext ctx, PodcastTranscriptCue cue) async {
    HapticFeedback.mediumImpact();
    final pos = cue.timed
        ? Duration(milliseconds: (cue.startSec * 1000).round())
        : _player.progressBarStatus.value.current;
    final bm =
        await PodcastBookmarkStore.add(widget.item, pos, quote: cue.text);
    if (bm == null || !ctx.mounted) return;
    showBookmarkSavedSnack(ctx, bm);
  }

  void _toggleSpoiler() {
    setState(() => _spoiler = !_spoiler);
    _prefs?.put(_spoilerKey, _spoiler);
  }

  // ── Search ──────────────────────────────────────────────────────────
  void _onQuery(List<PodcastTranscriptCue> cues, String q) {
    final m = transcriptMatches(cues, q);
    setState(() {
      _matches = m;
      _matchIdx = firstMatchFrom(m, _active.value < 0 ? 0 : _active.value);
    });
    _showMatch();
  }

  void _step(bool forward) {
    setState(() =>
        _matchIdx = stepMatch(_matchIdx, _matches.length, forward: forward));
    _showMatch();
  }

  void _showMatch() {
    if (_matchIdx < 0 || _matchIdx >= _matches.length) return;
    if (_follow) setState(() => _follow = false);
    _scrollTo(_matches[_matchIdx]);
  }

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _matches = const [];
      _matchIdx = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<LoadedTranscript>(
      future: _future,
      builder: (context, snap) {
        final t = snap.data;
        final done = snap.connectionState == ConnectionState.done;
        final cues = t?.cues ?? const <PodcastTranscriptCue>[];
        final timed = t?.timed ?? false;
        final source = t == null || !t.youtube
            ? null
            : (t.auto ? 'transcriptAutoCaptions'.tr : 'transcriptYoutube'.tr);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            if (_searching)
              _searchBar(cues, theme)
            else
              RiffSheetTitle(
                'transcript'.tr,
                subtitle: [widget.item.title, if (source != null) source]
                    .join(' · '),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cues.isNotEmpty)
                      IconButton(
                        tooltip: 'transcriptSearch'.tr,
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () => setState(() => _searching = true),
                      ),
                    if (timed)
                      IconButton(
                        tooltip: _spoiler
                            ? 'transcriptSpoilerOff'.tr
                            : 'transcriptSpoilerOn'.tr,
                        icon: _spoiler
                            ? Icon(Icons.visibility_off_outlined,
                                color: theme.colorScheme.secondary)
                            : const Icon(Icons.visibility_outlined),
                        onPressed: _toggleSpoiler,
                      ),
                    IconButton(
                      tooltip: 'episodeBookmarks'.tr,
                      icon: const Icon(Icons.bookmarks_outlined),
                      onPressed: () => showEpisodeBookmarksSheet(context),
                    ),
                  ],
                ),
              ),
            const RiffSheetDivider(),
            Expanded(
              child: !done
                  ? const Center(child: CircularProgressIndicator())
                  : cues.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('noTranscript'.tr,
                                textAlign: TextAlign.center,
                                style: homeCardSubtitleStyle(context)
                                    .copyWith(fontSize: 14)),
                          ),
                        )
                      : _list(cues, timed, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _searchBar(List<PodcastTranscriptCue> cues, ThemeData theme) {
    final has = _matches.isNotEmpty;
    final q = _searchCtrl.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (q) => _onQuery(cues, q),
              onSubmitted: (_) => _step(true),
              decoration: InputDecoration(
                hintText: 'transcriptSearch'.tr,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (q.isNotEmpty)
            Text(
              has
                  ? 'transcriptMatches'.trParams({
                      'current': '${_matchIdx + 1}',
                      'total': '${_matches.length}',
                    })
                  : 'transcriptNoMatches'.tr,
              style: homeCardSubtitleStyle(context).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          IconButton(
            tooltip: 'transcriptPrevMatch'.tr,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
            onPressed: has ? () => _step(false) : null,
          ),
          IconButton(
            tooltip: 'transcriptNextMatch'.tr,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: has ? () => _step(true) : null,
          ),
          IconButton(
            tooltip: 'close'.tr,
            icon: const Icon(Icons.close_rounded),
            onPressed: _closeSearch,
          ),
        ],
      ),
    );
  }

  Widget _list(List<PodcastTranscriptCue> cues, bool timed, ThemeData theme) {
    return Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            // A drag (not our own scrollTo) pauses auto-follow.
            if (timed && n.dragDetails != null && _follow) {
              setState(() => _follow = false);
            }
            return false;
          },
          child: Obx(() {
            // Segments and bookmarks change rarely; the active line is a
            // ValueNotifier so the 10 Hz tick doesn't rebuild this.
            PodcastBookmarkStore.rev.value;
            final segments = _isCurrent && timed
                ? _player.podcastSegments.toList()
                : const <PodcastSegment>[];
            final marked = {
              for (final b in PodcastBookmarkStore.forEpisode(widget.item.id))
                b.positionMs
            };
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
              itemCount: cues.length + 1,
              itemBuilder: (context, row) {
                if (row == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                    child: Text(
                        timed
                            ? 'transcriptHint'.tr
                            : 'transcriptHintUntimed'.tr,
                        style: homeCardSubtitleStyle(context)
                            .copyWith(fontSize: 12)),
                  );
                }
                final i = row - 1;
                final cue = cues[i];
                final seg = timed ? segmentAt(segments, cue.startSec) : null;
                final segStart = seg != null &&
                    (i == 0 ||
                        segmentAt(segments, cues[i - 1].startSec)?.id !=
                            seg.id);
                final isBookmarked = timed &&
                    marked.contains((cue.startSec * 1000).round());
                return ValueListenableBuilder<int>(
                  valueListenable: _active,
                  builder: (context, active, _) => _TranscriptLine(
                    cue: cue,
                    timed: timed,
                    active: timed && i == active,
                    blurred: _spoiler && timed && active >= 0 && i > active,
                    segment: seg,
                    segmentStart: segStart,
                    bookmarked: isBookmarked,
                    query: _searching ? _searchCtrl.text : '',
                    currentMatch: _matchIdx >= 0 &&
                        _matchIdx < _matches.length &&
                        _matches[_matchIdx] == i,
                    onTap: timed && _isCurrent ? () => _seekTo(i) : null,
                    onLongPress: () => _bookmark(context, cue),
                  ),
                );
              },
            );
          }),
        ),
        if (timed && !_follow && _isCurrent)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: RiffChoiceChip(
                icon: Icons.my_location_rounded,
                selected: true,
                label: 'transcriptResync'.tr,
                onTap: _resync,
              ),
            ),
          ),
      ],
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({
    required this.cue,
    required this.timed,
    required this.active,
    required this.blurred,
    required this.segment,
    required this.segmentStart,
    required this.bookmarked,
    required this.query,
    required this.currentMatch,
    required this.onTap,
    required this.onLongPress,
  });

  final PodcastTranscriptCue cue;
  final bool timed;
  final bool active;
  final bool blurred;
  final PodcastSegment? segment;
  final bool segmentStart;
  final bool bookmarked;
  final String query;
  final bool currentMatch;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final normal = theme.textTheme.titleMedium?.color;
    final dim = theme.textTheme.bodySmall?.color?.withOpacity(0.6);
    final base = TextStyle(
      fontSize: 15,
      height: 1.42,
      color: active ? accent : normal,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
    );
    final ranges = matchRanges(cue.text, query);
    final hl = accent.withOpacity(currentMatch ? 0.55 : 0.25);
    final spans = <InlineSpan>[
      if (cue.speaker != null)
        TextSpan(
            text: '${cue.speaker}  ',
            style: base.copyWith(fontWeight: FontWeight.w700)),
    ];
    var at = 0;
    for (final (a, b) in ranges) {
      if (a > at) spans.add(TextSpan(text: cue.text.substring(at, a)));
      spans.add(TextSpan(
          text: cue.text.substring(a, b),
          style: TextStyle(backgroundColor: hl, color: normal)));
      at = b;
    }
    if (at < cue.text.length) spans.add(TextSpan(text: cue.text.substring(at)));

    Widget text = Text.rich(TextSpan(style: base, children: spans));
    if (blurred) {
      text = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: text,
      );
    }

    final seg = segment;
    Widget line = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (timed)
              SizedBox(
                width: 54,
                child: Row(
                  children: [
                    Text(
                      formatSegmentLength(cue.startSec),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? accent : dim,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (bookmarked)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(Icons.bookmark_rounded,
                            size: 12, color: accent),
                      ),
                  ],
                ),
              ),
            Expanded(child: text),
          ],
        ),
      ),
    );

    if (seg == null) return line;
    return Container(
      decoration: BoxDecoration(
        color: seg.category.color.withOpacity(0.10),
        border: Border(
            left: BorderSide(color: seg.category.color.withOpacity(0.8), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (segmentStart)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(
                seg.category.labelKey.tr.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: seg.category.color),
              ),
            ),
          line,
        ],
      ),
    );
  }
}
