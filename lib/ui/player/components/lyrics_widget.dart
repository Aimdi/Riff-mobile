import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:get/get.dart';

import '/services/lyrics_romanization.dart';
import '/services/lyrics_text_size.dart';
import '/services/lyrics_timing.dart';
import '../../widgets/loader.dart';
import '../player_controller.dart';
import 'lyric_seek_line.dart';
import 'word_synced_lyrics.dart';
import '/ui/theme/riff_tokens.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  /// A tap on synced lyrics, which take touches themselves (drag to browse
  /// them): the host's own tap action, e.g. closing the lyrics.
  final VoidCallback? onTap;
  const LyricsWidget({super.key, required this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    // Lyrics text size, on top of the phone's font size: Text below picks
    // it up, and RiffLyricUI sizes the synced reader's lines with it.
    return Obx(() {
      final media = MediaQuery.of(context);
      return MediaQuery(
        data: media.copyWith(
            textScaler: ScaledTextScaler(
                media.textScaler, LyricsTextSize.selected.value.factor)),
        child: Builder(builder: _lyrics),
      );
    });
  }

  Widget _lyrics(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    // Outer Obx: loading / mode / lyric payload only — NOT progress ticks.
    return Obx(
      () {
        if (playerController.isLyricsLoading.isTrue) {
          return const Center(child: LoadingIndicator());
        }
        final theme = Theme.of(context);
        // Read here so switching it in Settings redraws the lyrics.
        final romanized = LyricsRomanization.enabled.isTrue;
        if (playerController.lyricsMode.toInt() == 1) {
          final plain = playerController.lyrics["plainLyrics"] == "NA"
              ? "lyricsNotAvailable".tr
              : (playerController.lyrics["plainLyrics"] ?? "").toString();
          return Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: padding,
              child: TextSelectionTheme(
                data: Theme.of(context).textSelectionTheme,
                child: SelectableText.rich(
                  romanizedLyricsText(
                    plain,
                    style: theme.textTheme.titleLarge!
                        .copyWith(color: theme.colorScheme.onSurface),
                    romanStyle: theme.textTheme.bodyMedium!
                        .copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final ttml = (playerController.lyrics['ttml'] ?? '').toString();
        if (ttml.isNotEmpty) {
          return WordSyncedLyricsWidget(
              key: ValueKey(romanized), ttml: ttml, padding: padding);
        }
        final model = LyricsModelBuilder.create()
            .bindLyricToMain(playerController.lyrics['synced'].toString())
            .getModel();
        // Romanization goes in each line's second line.
        for (final line in model.lyrics) {
          line.extText = LyricsRomanization.lineFor(line.mainText);
        }
        // Built here (not per progress tick): a new LyricUI makes the
        // reader re-layout.
        final lyricUi = RiffLyricUI.of(context, playerController.lyricUi);
        // Nested Obx: only the playhead position updates ~10Hz.
        return Obx(() {
          // Lyrics timing: this song's lyrics may show later or earlier.
          final delay =
              LyricsTiming.delayMs(playerController.currentSong.value?.id);
          final pos = lyricsPositionMs(
              playerController.progressBarStatus.value.current.inMilliseconds,
              delay);
          // Drag to look through the lyrics; the line in the middle gets
          // its time and ▶ to play from there (Spotify and Apple Music
          // jump to a tapped line; a tap here keeps closing the lyrics).
          return _SeekableLyricsReader(
            padding: const EdgeInsets.only(left: 5, right: 5),
            lyricUi: lyricUi,
            position: pos,
            model: model,
            onTap: onTap,
            selectLineBuilder: (progress, confirm) => LyricSeekLine(
              positionMs: songPositionForLyricMs(progress, delay),
              onSeek: () {
                confirm();
                playerController.seek(Duration(
                    milliseconds: songPositionForLyricMs(progress, delay)));
              },
            ),
            emptyBuilder: () => Center(
              child: Text(
                "syncedLyricsNotAvailable".tr,
                style: theme.textTheme.titleMedium!
                    .copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          );
        });
      },
    );
  }
}

/// Plain lyrics as one text, each line followed by its romanization (in
/// [romanStyle]) when [LyricsRomanization] gives one.
TextSpan romanizedLyricsText(String lyrics,
    {required TextStyle style, required TextStyle romanStyle}) {
  final lines = lyrics.split('\n');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < lines.length; i++) ...[
        TextSpan(text: lines[i]),
        if (LyricsRomanization.lineFor(lines[i]) case final roman?)
          TextSpan(text: '\n$roman', style: romanStyle),
        if (i < lines.length - 1) const TextSpan(text: '\n'),
      ],
    ],
  );
}

/// [LyricsReader] that keeps following the song after a touch it lost:
/// it marks every touch as a drag on tap-down and clears that on tap-up,
/// so a touch the host takes as a long-press (song menu) left the lyrics
/// stuck where they were.
class _SeekableLyricsReader extends LyricsReader {
  _SeekableLyricsReader({
    super.position,
    super.model,
    super.padding,
    super.lyricUi,
    super.onTap,
    super.selectLineBuilder,
    super.emptyBuilder,
  });

  @override
  State<StatefulWidget> createState() => _SeekableLyricsReaderState();
}

class _SeekableLyricsReaderState extends LyricReaderState {
  void _touchEnded(PointerEvent _) => isDrag = false;

  @override
  Widget buildTouchReader(child) => Listener(
        onPointerUp: _touchEnded,
        onPointerCancel: _touchEnded,
        child: super.buildTouchReader(child),
      );
}

/// Synced (line-level) lyrics in the Lights-out type: the current line
/// `titleLarge` in the text colour, the others `titleLarge` in the secondary
/// colour at 60%, second lines (romanization) `bodyMedium` in the secondary
/// colour, dimmed off the current line; all at the phone's font size times
/// Lyrics text size. Keeps the controller's layout (gaps, bias, alignment,
/// highlight sweep); the sweep is playback progress, so it is drawn in the
/// accent.
class RiffLyricUI extends UINetease {
  RiffLyricUI._(
    UINetease base, {
    required this.playing,
    required this.other,
    required this.playingExt,
    required this.otherExt,
    required this.sweep,
  }) : super(
          defaultSize: playing.fontSize ?? base.defaultSize,
          otherMainSize: other.fontSize ?? base.otherMainSize,
          defaultExtSize: playingExt.fontSize ?? base.defaultExtSize,
          bias: base.bias,
          lineGap: base.lineGap,
          inlineGap: base.inlineGap,
          lyricAlign: base.lyricAlign,
          lyricBaseLine: base.lyricBaseLine,
          highlight: base.highlight,
          highlightDirection: base.highlightDirection,
        );

  factory RiffLyricUI.of(BuildContext context, UINetease base) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The reader paints its lines without a text scaler: they take the
    // phone's font size and Lyrics text size from here.
    final scaler = MediaQuery.textScalerOf(context);
    final main = scaledTextStyle(theme.textTheme.titleLarge!, scaler);
    final ext = scaledTextStyle(theme.textTheme.bodyMedium!, scaler);
    final dim =
        scheme.onSurfaceVariant.withOpacity(RiffPalette.lyricsDimOpacity);
    return RiffLyricUI._(
      base,
      playing: main.copyWith(color: scheme.onSurface),
      other: main.copyWith(color: dim),
      playingExt: ext.copyWith(color: scheme.onSurfaceVariant),
      otherExt: ext.copyWith(color: dim),
      sweep: scheme.secondary,
    );
  }

  final TextStyle playing;
  final TextStyle other;
  final TextStyle playingExt;
  final TextStyle otherExt;
  final Color sweep;

  @override
  TextStyle getPlayingMainTextStyle() => playing;

  @override
  TextStyle getOtherMainTextStyle() => other;

  @override
  TextStyle getPlayingExtTextStyle() => playingExt;

  @override
  TextStyle getOtherExtTextStyle() => otherExt;

  @override
  Color getLyricHightlightColor() => sweep;
}
