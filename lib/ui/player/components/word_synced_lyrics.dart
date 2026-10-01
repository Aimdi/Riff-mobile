import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/better_lyrics_service.dart';
import '/ui/player/player_controller.dart';

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
  final _scroll = ScrollController();
  final _player = Get.find<PlayerController>();

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
    _progressWorker?.dispose();
    _activeLine.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActive(estimateIfUnbuilt: true);
    });
  }

  /// Keeps the active line ~2 rows below the top, like before, but without a
  /// fixed item extent (which clipped wrapped / enlarged active lines).
  void _scrollToActive({required bool estimateIfUnbuilt}) {
    if (!_scroll.hasClients || _lines.isEmpty) return;
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
              ?.copyWith(color: Colors.white),
        ),
      );
    }
    final accent = Theme.of(context).colorScheme.secondary;

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: widget.padding.add(const EdgeInsets.symmetric(vertical: 24)),
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
              if (line.hasWords) {
                if (isActive) {
                  return Obx(() => _wordLine(context, accent, line,
                      posSec: _posSec, isActive: true, isPast: false));
                }
                return _wordLine(context, accent, line,
                    posSec: 0, isActive: false, isPast: isPast);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: _lineStyle(context, accent,
                      isActive: isActive, isPast: isPast),
                ),
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
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  TextStyle _lineStyle(
    BuildContext context,
    Color accent, {
    required bool isActive,
    required bool isPast,
  }) {
    final base = Theme.of(context).textTheme.titleMedium!;
    if (isActive) {
      return base.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: (base.fontSize ?? 16) + 2,
      );
    }
    return base.copyWith(
      color: Colors.white.withOpacity(isPast ? 0.35 : 0.55),
      fontWeight: FontWeight.w400,
    );
  }

  TextStyle _wordStyle(
    BuildContext context,
    Color accent, {
    required bool isActive,
    required bool isPast,
  }) {
    final base = Theme.of(context).textTheme.titleMedium!;
    if (isActive) {
      return base.copyWith(
        color: accent,
        fontWeight: FontWeight.w800,
        fontSize: (base.fontSize ?? 16) + 3,
      );
    }
    if (isPast) {
      return base.copyWith(
        color: Colors.white.withOpacity(0.45),
        fontWeight: FontWeight.w500,
      );
    }
    return base.copyWith(
      color: Colors.white.withOpacity(0.55),
      fontWeight: FontWeight.w400,
    );
  }
}
