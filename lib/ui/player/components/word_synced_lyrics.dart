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

class _WordSyncedLyricsWidgetState extends State<WordSyncedLyricsWidget> {
  late final List<TtmlLine> _lines =
      BetterLyricsService.parseTimedLines(widget.ttml);
  final _scroll = ScrollController();
  int _lastScrollLine = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeScroll(int activeLine) {
    if (_lastScrollLine == activeLine || !_scroll.hasClients) return;
    _lastScrollLine = activeLine;
    final index = (activeLine - 2).clamp(0, _lines.length - 1);
    final target =
        (index * 40.0).clamp(0.0, _scroll.position.maxScrollExtent);
    if ((_scroll.offset - target).abs() < 40) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
    final player = Get.find<PlayerController>();
    final accent = Theme.of(context).colorScheme.secondary;

    return Obx(() {
      final posSec =
          player.progressBarStatus.value.current.inMilliseconds / 1000.0;
      var activeLine = 0;
      for (var i = 0; i < _lines.length; i++) {
        if (_lines[i].beginSec <= posSec) activeLine = i;
      }
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeScroll(activeLine));

      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: widget.padding.add(const EdgeInsets.symmetric(vertical: 24)),
        controller: _scroll,
        itemCount: _lines.length,
        itemExtent: 40,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, i) {
          final line = _lines[i];
          final isActive = i == activeLine;
          final isPast = i < activeLine;
          if (line.hasWords) {
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
                              (isActive &&
                                  posSec >= (w.endSec ?? w.beginSec)),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            );
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
      );
    });
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
