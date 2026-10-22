import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/lyrics_timing.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';
import '../lrc_lines.dart';
import '../player_controller.dart';

/// The lyric line being sung right now, under the title of the full
/// player; tap for the full lyrics. Only songs with synced lyrics show it,
/// and it slides in once they've loaded. Across a skip it keeps its room
/// (the old line fading out) until the next song's lyrics are in, so the
/// title and controls don't drop and rise again a moment later.
class LyricLinePreview extends StatefulWidget {
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
  State<LyricLinePreview> createState() => _LyricLinePreviewState();
}

/// Whether [lyrics] are the playing song's answer (some found, or known to
/// be none) rather than the blank a new song starts with.
bool lyricsKnown(Map<String, dynamic> lyrics) =>
    lyrics.containsKey('source') ||
    lyrics['offline'] == true ||
    [lyrics['synced'], lyrics['plainLyrics'], lyrics['ttml']]
        .any((v) => (v ?? '').toString().isNotEmpty);

class _LyricLinePreviewState extends State<LyricLinePreview> {
  /// The line on show and what it is (song and line), kept while the next
  /// song's lyrics load.
  String? _text;
  String? _textKey;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: RiffDurations.sheet,
      curve: RiffDurations.selectCurve,
      alignment: Alignment.bottomCenter,
      child: Obx(() {
        final lyrics = playerController.lyrics;
        final synced = (lyrics['synced'] ?? '').toString();
        final lines = synced.isEmpty
            ? const <LrcLine>[]
            : LyricLinePreview._linesFor(synced);
        var held = false;
        if (playerController.usesLongFormTransport) {
          _text = null;
        } else if (lines.isEmpty) {
          // A new song whose lyrics aren't in yet: hold the line's room,
          // faded out. Known to have none: it closes up.
          held = _text != null && !lyricsKnown(lyrics);
          if (!held) _text = null;
        } else {
          final song = playerController.currentSong.value;
          // Moved by this song's lyrics timing, as the lyrics are.
          final i = lrcLineAt(
              lines,
              Duration(
                  milliseconds: lyricsPositionMs(
                      playerController
                          .progressBarStatus.value.current.inMilliseconds,
                      LyricsTiming.delayMs(song?.id))));
          // Before the first line: a note, like an instrumental intro.
          _text = i < 0 ? '♪' : lines[i].text;
          _textKey = '${song?.id}_$i';
        }
        final text = _text;
        if (text == null) return const SizedBox(width: double.infinity);
        final fg = theme.colorScheme.onSurface;
        return Padding(
          padding: const EdgeInsets.only(bottom: RiffSpacing.md),
          child: IgnorePointer(
            ignoring: held,
            child: ExcludeSemantics(
              excluding: held,
              child: AnimatedOpacity(
                opacity: held ? 0 : 1,
                duration: RiffDurations.content,
                curve:
                    held ? RiffDurations.exitCurve : RiffDurations.enterCurve,
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
                          child: RiffSwitcher(
                            duration: RiffDurations.content,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              text,
                              key: ValueKey<String?>(_textKey),
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
                            color:
                                fg.withOpacity(RiffPalette.lyricsDimOpacity)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
