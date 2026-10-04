import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:get/get.dart';

import '../../widgets/loader.dart';
import '../player_controller.dart';
import 'word_synced_lyrics.dart';
import '/ui/theme/riff_tokens.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    // Outer Obx: loading / mode / lyric payload only — NOT progress ticks.
    return Obx(
      () {
        if (playerController.isLyricsLoading.isTrue) {
          return const Center(child: LoadingIndicator());
        }
        final theme = Theme.of(context);
        if (playerController.lyricsMode.toInt() == 1) {
          return Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: padding,
              child: TextSelectionTheme(
                data: Theme.of(context).textSelectionTheme,
                child: SelectableText(
                  playerController.lyrics["plainLyrics"] == "NA"
                      ? "lyricsNotAvailable".tr
                      : playerController.lyrics["plainLyrics"] ?? "",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge!
                      .copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          );
        }
        final ttml = (playerController.lyrics['ttml'] ?? '').toString();
        if (ttml.isNotEmpty) {
          return WordSyncedLyricsWidget(ttml: ttml, padding: padding);
        }
        final model = LyricsModelBuilder.create()
            .bindLyricToMain(playerController.lyrics['synced'].toString())
            .getModel();
        // Built here (not per progress tick): a new LyricUI makes the
        // reader re-layout.
        final lyricUi = RiffLyricUI.of(context, playerController.lyricUi);
        // Nested Obx: only the playhead position updates ~10Hz.
        return Obx(() {
          final pos =
              playerController.progressBarStatus.value.current.inMilliseconds;
          return IgnorePointer(
            child: LyricsReader(
              padding: const EdgeInsets.only(left: 5, right: 5),
              lyricUi: lyricUi,
              position: pos,
              model: model,
              emptyBuilder: () => Center(
                child: Text(
                  "syncedLyricsNotAvailable".tr,
                  style: theme.textTheme.titleMedium!
                      .copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

/// Synced (line-level) lyrics in the Lights-out type: the current line
/// `titleLarge` in the text colour, the others `titleLarge` in the secondary
/// colour at 60%, translations `labelSmall`. Keeps the controller's layout
/// (gaps, bias, alignment, highlight sweep); the sweep is playback progress,
/// so it is drawn in the accent.
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
    final text = theme.textTheme;
    final dim =
        scheme.onSurfaceVariant.withOpacity(RiffPalette.lyricsDimOpacity);
    return RiffLyricUI._(
      base,
      playing: text.titleLarge!.copyWith(color: scheme.onSurface),
      other: text.titleLarge!.copyWith(color: dim),
      playingExt: text.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
      otherExt: text.labelSmall!.copyWith(color: dim),
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
