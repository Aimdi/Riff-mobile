import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '../lrc_lines.dart';
import '../player_controller.dart';

/// The lyric line being sung right now, under the title of the full
/// player; tap for the full lyrics. Only songs with synced lyrics show it,
/// and it slides in once they've loaded.
class LyricLinePreview extends StatelessWidget {
  const LyricLinePreview({super.key});

  // The LRC text only changes per song: parse it once, not on every tick.
  static String? _source;
  static List<LrcLine> _lines = const [];

  static List<LrcLine> _linesFor(String lrc) {
    if (lrc != _source) {
      _source = lrc;
      _lines = parseLrc(lrc);
    }
    return _lines;
  }

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: RiffDurations.sheet,
      curve: RiffDurations.selectCurve,
      alignment: Alignment.bottomCenter,
      child: Obx(() {
        final synced = (playerController.lyrics['synced'] ?? '').toString();
        final lines = synced.isEmpty ? const <LrcLine>[] : _linesFor(synced);
        if (playerController.usesLongFormTransport || lines.isEmpty) {
          return const SizedBox(width: double.infinity);
        }
        final i = lrcLineAt(
            lines, playerController.progressBarStatus.value.current);
        // Before the first line: a note, like an instrumental intro.
        final text = i < 0 ? '♪' : lines[i].text;
        final fg = theme.colorScheme.onSurface;
        return Padding(
          padding: const EdgeInsets.only(bottom: RiffSpacing.md),
          child: Semantics(
            button: true,
            label: 'lyrics'.tr,
            child: InkWell(
              borderRadius: BorderRadius.circular(RiffRadii.xs),
              onTap: () {
                if (playerController.showLyricsflag.isFalse) {
                  playerController.showLyrics();
                }
              },
              child: Row(
                children: [
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: RiffDurations.sheet,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, if (current != null) current],
                      ),
                      child: Text(
                        text,
                        key: ValueKey<int>(i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: fg),
                      ),
                    ),
                  ),
                  const SizedBox(width: RiffSpacing.xs),
                  Icon(Icons.chevron_right_rounded,
                      size: RiffComponentSizes.trailingIcon,
                      color: fg.withOpacity(RiffPalette.lyricsDimOpacity)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
