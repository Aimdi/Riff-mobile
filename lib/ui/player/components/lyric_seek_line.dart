import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';

/// "1:23" for a line starting [ms] into the song ("1:02:03" past an hour).
String lyricTimeLabel(int ms) {
  final d = Duration(milliseconds: ms < 0 ? 0 : ms);
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${m.toString().padLeft(2, '0')}:$s'
      : '$m:$s';
}

/// Shown across the middle of synced lyrics while they're being browsed:
/// the time of the line there, a hairline and ▶ to play from that line (in
/// the accent, as play buttons are).
class LyricSeekLine extends StatelessWidget {
  const LyricSeekLine(
      {super.key, required this.positionMs, required this.onSeek});

  final int positionMs;
  final VoidCallback onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: RiffSpacing.lg),
      child: Row(
        children: [
          // Only ▶ takes touches, so a drag over the line still scrolls.
          Expanded(
            child: IgnorePointer(
              child: Row(
                children: [
                  Text(
                    lyricTimeLabel(positionMs),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: RiffSpacing.sm),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'playFromHere'.tr,
            onPressed: onSeek,
            icon: Icon(Icons.play_arrow_rounded,
                color: theme.colorScheme.secondary),
          ),
        ],
      ),
    );
  }
}
