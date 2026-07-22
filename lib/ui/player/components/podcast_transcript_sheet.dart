import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '/services/podcast_service.dart';
import '../player_controller.dart';

/// Spotify-style episode transcript viewer (Podcasting 2.0
/// `<podcast:transcript>`): the current line follows playback and stays
/// highlighted; tapping a line seeks to it. When the feed only offers an
/// untimed transcript (plain text/HTML) it renders as readable paragraphs
/// without live sync.
class PodcastTranscriptSheet extends StatefulWidget {
  const PodcastTranscriptSheet({super.key, required this.url, this.type = ''});
  final String url;
  final String type;

  static void open(BuildContext context,
      {required String url, String type = ''}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: PodcastTranscriptSheet(url: url, type: type),
      ),
    );
  }

  @override
  State<PodcastTranscriptSheet> createState() => _PodcastTranscriptSheetState();
}

class _PodcastTranscriptSheetState extends State<PodcastTranscriptSheet> {
  late final Future<List<PodcastTranscriptCue>> _future;
  final _scroll = ItemScrollController();

  /// Auto-scroll follows playback until the user scrolls by hand.
  bool _follow = true;
  int _lastAutoScrolled = -1;

  @override
  void initState() {
    super.initState();
    _future = PodcastService.transcript(widget.url, type: widget.type);
  }

  int _activeIndex(List<PodcastTranscriptCue> cues, double posSec) {
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

  void _scrollTo(int index, {bool jump = false}) {
    if (!_scroll.isAttached) return;
    _scroll.scrollTo(
      index: index < 0 ? 0 : index,
      alignment: 0.35,
      duration: jump
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  String _fmt(double sec) {
    final d = Duration(milliseconds: (sec * 1000).round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playerController = Get.find<PlayerController>();
    final song = playerController.currentSong.value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('transcript'.tr, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            song?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          const Divider(height: 20),
          Expanded(
            child: FutureBuilder<List<PodcastTranscriptCue>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final cues = snap.data ?? const <PodcastTranscriptCue>[];
                if (cues.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('noTranscript'.tr,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ),
                  );
                }
                final synced = cues.first.startSec >= 0;
                if (!synced) return _plainList(cues, theme);
                return _syncedList(cues, theme, playerController);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Untimed transcript: plain readable paragraphs.
  Widget _plainList(List<PodcastTranscriptCue> cues, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: cues.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          cues[i].speaker != null
              ? '${cues[i].speaker}: ${cues[i].text}'
              : cues[i].text,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
      ),
    );
  }

  /// Timed transcript with live highlight + tap-to-seek.
  Widget _syncedList(List<PodcastTranscriptCue> cues, ThemeData theme,
      PlayerController playerController) {
    final accent = theme.colorScheme.secondary;
    final normal = theme.textTheme.bodyMedium?.color;
    final dim = theme.textTheme.bodySmall?.color?.withOpacity(0.6);
    return Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          onNotification: (n) {
            // A drag (not our own animateTo) pauses auto-follow.
            if (n.dragDetails != null && _follow) {
              setState(() => _follow = false);
            }
            return false;
          },
          child: Obx(() {
            final posSec = playerController
                    .progressBarStatus.value.current.inMilliseconds /
                1000.0;
            final active = _activeIndex(cues, posSec);
            if (_follow && active >= 0 && active != _lastAutoScrolled) {
              _lastAutoScrolled = active;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _follow) _scrollTo(active);
              });
            }
            return ScrollablePositionedList.builder(
              itemScrollController: _scroll,
              padding: const EdgeInsets.only(bottom: 70),
              itemCount: cues.length,
              itemBuilder: (context, i) {
                final cue = cues[i];
                final isActive = i == active;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    playerController.seek(Duration(
                        milliseconds: (cue.startSec * 1000).round()));
                    setState(() => _follow = true);
                    _scrollTo(i);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            _fmt(cue.startSec),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: isActive ? accent : dim,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            cue.speaker != null
                                ? '${cue.speaker}: ${cue.text}'
                                : cue.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.35,
                              color: isActive ? accent : normal,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ),
        if (!_follow)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActionChip(
                avatar: Icon(Icons.play_circle_outline,
                    size: 18, color: theme.colorScheme.secondary),
                label: Text('followPlayback'.tr),
                onPressed: () {
                  setState(() => _follow = true);
                  _lastAutoScrolled = -1;
                },
              ),
            ),
          ),
      ],
    );
  }
}
