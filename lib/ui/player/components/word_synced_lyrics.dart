import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/better_lyrics_service.dart';
import '/services/lyrics_romanization.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import 'lyric_seek_line.dart';

/// Word-level synced lyrics from Better Lyrics TTML.
class WordSyncedLyricsWidget extends StatefulWidget {
  const WordSyncedLyricsWidget({
    super.key,
    required this.ttml,
    required this.padding,
  });

  final String ttml;
  final EdgeInsetsGeometry padding;

  @override
  State<WordSyncedLyricsWidget> createState() => _WordSyncedLyricsWidgetState();
}

/// Index of the last line whose start is at/before [posSec] (0 when none).
int wordSyncedActiveLine(List<TtmlLine> lines, double posSec) {
  var activeLine = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].beginSec <= posSec) activeLine = i;
  }
  return activeLine;
}

class _WordSyncedLyricsWidgetState extends State<WordSyncedLyricsWidget> {
  late final List<TtmlLine> _lines =
      BetterLyricsService.parseTimedLines(widget.ttml);

  /// Each line's romanization (null: none), worked out once.
  late final List<String?> _romanized = [
    for (final line in _lines) LyricsRomanization.lineFor(line.text),
  ];
  final _scroll = ScrollController();
  final _player = Get.find<PlayerController>();

  /// While the user scrolls the lyrics (and [_browseLinger] after): the
  /// list stops following the song and the line in the middle gets
  /// [LyricSeekLine] to play from it.
  final _browsing = ValueNotifier<bool>(false);
  final _centerLine = ValueNotifier<int>(0);
  final _listKey = GlobalKey();
  Timer? _browseEnd;
  static const _browseLinger = Duration(seconds: 3);

  /// Active line, derived from the 10 Hz progress tick but only notifying
  /// when the line actually changes — rows rebuild per line, not per tick.
  /// Only the active word-timed row follows the tick (word highlighting).
  final _activeLine = ValueNotifier<int>(0);
  final _rowKeys = <int, GlobalKey>{};
  Worker? _progressWorker;

  double get _posSec =>
      _player.progressBarStatus.value.current.inMilliseconds / 1000.0;

  @override
  void initState() {
    super.initState();
    _activeLine.value = wordSyncedActiveLine(_lines, _posSec);
    _progressWorker = ever(_player.progressBarStatus, (_) {
      _activeLine.value = wordSyncedActiveLine(_lines, _posSec);
    });
    _activeLine.addListener(_scheduleScroll);
    _scheduleScroll();
  }

  @override
  void dispose() {
    _browseEnd?.cancel();
    _progressWorker?.dispose();
    _activeLine.dispose();
    _browsing.dispose();
    _centerLine.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _browseEnd?.cancel();
      _browsing.value = true;
    }
    if (!_browsing.value) return false;
    _centerLine.value = _lineAtCenter() ?? _centerLine.value;
    if (n is ScrollEndNotification) {
      _browseEnd?.cancel();
      _browseEnd = Timer(_browseLinger, _stopBrowsing);
    }
    return false;
  }

  void _stopBrowsing() {
    _browseEnd?.cancel();
    if (!mounted) return;
    _browsing.value = false;
    _scheduleScroll();
  }

  /// The built row nearest the middle of the list.
  int? _lineAtCenter() {
    final list = _listKey.currentContext?.findRenderObject();
    if (list is! RenderBox || !list.hasSize) return null;
    final middle = list.size.height / 2;
    int? best;
    var bestDistance = double.infinity;
    _rowKeys.forEach((i, key) {
      final row = key.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) return;
      final top = row.localToGlobal(Offset.zero, ancestor: list).dy;
      final distance = (top + row.size.height / 2 - middle).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    });
    return best;
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActive(estimateIfUnbuilt: true);
    });
  }

  /// Keeps the active line ~2 rows below the top, like before, but without a
  /// fixed item extent (which clipped wrapped / enlarged active lines).
  void _scrollToActive({required bool estimateIfUnbuilt}) {
    if (!_scroll.hasClients || _lines.isEmpty || _browsing.value) return;
    final position = _scroll.position;
    final viewport = position.viewportDimension;
    final alignment = viewport <= 0 ? 0.0 : (104 / viewport).clamp(0.0, 0.5);
    final ctx = _rowKeys[_activeLine.value]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: alignment,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!estimateIfUnbuilt) return;
    // Row not laid out (user scrolled far away) — jump near it using the
    // average row height, then align precisely once it's built.
    final avgRow = (position.maxScrollExtent + viewport) / _lines.length;
    final estimate = (avgRow * _activeLine.value - alignment * viewport)
        .clamp(0.0, position.maxScrollExtent);
    _scroll.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActive(estimateIfUnbuilt: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          'syncedLyricsNotAvailable'.tr,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
      );
    }
    final accent = Theme.of(context).colorScheme.secondary;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: KeyedSubtree(key: _listKey, child: _list(accent)),
        ),
        // Only ▶ takes touches: drags anywhere else still scroll.
        Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: _browsing,
            builder: (context, browsing, _) => !browsing
                ? const SizedBox.shrink()
                : ValueListenableBuilder<int>(
                    valueListenable: _centerLine,
                    builder: (context, i, _) => LyricSeekLine(
                      positionMs: (_lines[i].beginSec * 1000).round(),
                      onSeek: () {
                        _player.seek(Duration(
                            milliseconds: (_lines[i].beginSec * 1000).round()));
                        _stopBrowsing();
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _list(Color accent) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: widget.padding
          .add(const EdgeInsets.symmetric(vertical: RiffSpacing.xxl)),
      controller: _scroll,
      itemCount: _lines.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, i) {
        return KeyedSubtree(
          key: _rowKeys.putIfAbsent(i, GlobalKey.new),
          child: ValueListenableBuilder<int>(
            valueListenable: _activeLine,
            builder: (context, activeLine, _) {
              final line = _lines[i];
              final isActive = i == activeLine;
              final isPast = i < activeLine;
              final Widget row;
              if (line.hasWords) {
                row = isActive
                    ? Obx(() => _wordLine(context, accent, line,
                        posSec: _posSec, isActive: true, isPast: false))
                    : _wordLine(context, accent, line,
                        posSec: 0, isActive: false, isPast: isPast);
              } else {
                row = Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: _lineStyle(context, accent,
                        isActive: isActive, isPast: isPast),
                  ),
                );
              }
              final roman = _romanized[i];
              if (roman == null) return row;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row,
                  Padding(
                    padding: const EdgeInsets.only(bottom: RiffSpacing.xs),
                    child: Text(
                      roman,
                      textAlign: TextAlign.center,
                      style: _romanStyle(context, isActive: isActive),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _wordLine(
    BuildContext context,
    Color accent,
    TtmlLine line, {
    required double posSec,
    required bool isActive,
    required bool isPast,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text.rich(
        TextSpan(
          children: [
            for (final w in line.words)
              TextSpan(
                text: '${w.text} ',
                style: _wordStyle(
                  context,
                  accent,
                  isActive: isActive &&
                      posSec >= w.beginSec &&
                      (w.endSec == null || posSec < w.endSec!),
                  isPast: isPast ||
                      (isActive && posSec >= (w.endSec ?? w.beginSec)),
                  inActiveLine: isActive,
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// Lines are `titleLarge`: the current one in the text colour, the
  /// others (sung or still to come) in the secondary colour at 60%.
  TextStyle _lineStyle(
    BuildContext context,
    Color accent, {
    required bool isActive,
    required bool isPast,
  }) {
    final theme = Theme.of(context);
    final base = theme.textTheme.titleLarge!;
    if (isActive) return base.copyWith(color: theme.colorScheme.onSurface);
    return base.copyWith(
      color: theme.colorScheme.onSurfaceVariant
          .withOpacity(RiffPalette.lyricsDimOpacity),
    );
  }

  /// A line's romanization: `bodyMedium` in the secondary colour, dimmed
  /// off the current line, as the line-synced lyrics' second lines.
  TextStyle _romanStyle(BuildContext context, {required bool isActive}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return theme.textTheme.bodyMedium!.copyWith(
      color: isActive ? muted : muted.withOpacity(RiffPalette.lyricsDimOpacity),
    );
  }

  /// Words of a word-timed line: as [_lineStyle], except the word being
  /// sung, which is drawn in the accent (playback progress) and grows a
  /// little for karaoke emphasis (computed size, documented exception).
  TextStyle _wordStyle(
    BuildContext context,
    Color accent, {
    required bool isActive,
    required bool isPast,
    required bool inActiveLine,
  }) {
    if (isActive) {
      final base = Theme.of(context).textTheme.titleLarge!;
      return base.copyWith(
        color: accent,
        fontSize: (base.fontSize ?? _fallbackSize) + _activeWordGrowth,
      );
    }
    return _lineStyle(context, accent, isActive: inActiveLine, isPast: isPast);
  }

  /// Emphasis of the word being sung over the line size (was +1 over the
  /// active line before the restyle, kept).
  static const double _activeWordGrowth = 1;
  static const double _fallbackSize = 20;
}
