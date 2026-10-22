import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';
import 'package:get/get.dart';

import '/services/lyrics_romanization.dart';
import '/services/lyrics_text_size.dart';
import '/services/lyrics_timing.dart';
import '/services/lyrics_translation.dart';
import '../../widgets/loader.dart';
import '../lrc_lines.dart';
import '../player_controller.dart';
import 'lyric_seek_line.dart';
import 'word_synced_lyrics.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_motion.dart';

/// Lyrics fading out to nothing at the top and bottom edges (Spotify,
/// Apple Music), so a line the edge cuts isn't left half there.
class LyricsEdgeFade extends StatelessWidget {
  const LyricsEdgeFade({super.key, required this.child});
  final Widget child;

  /// The mask, kept while the lyrics' size stays put (they repaint as the
  /// lines move on).
  static Shader? _mask;
  static Size? _maskFor;

  static Shader _maskShader(Size size, Color opaque) {
    if (_mask == null || _maskFor != size) {
      _maskFor = size;
      _mask = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          opaque.withOpacity(0),
          opaque,
          opaque,
          opaque.withOpacity(0),
        ],
        stops: const [0, 0.1, 0.9, 1],
      ).createShader(Offset.zero & size);
    }
    return _mask!;
  }

  @override
  Widget build(BuildContext context) {
    // Only the mask's alpha counts.
    final opaque = Theme.of(context).colorScheme.surface.withOpacity(1);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => _maskShader(rect.size, opaque),
      child: child,
    );
  }
}

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
    return _LoadingSwap(
        loaded: (context) => _loaded(context, playerController));
  }

  Widget _loaded(BuildContext context, PlayerController playerController) {
    final theme = Theme.of(context);
    // Read here so switching it in Settings redraws the lyrics.
    final romanized = LyricsRomanization.enabled.isTrue;
    // None for want of a connection (they come once it's back).
    final offline = playerController.lyrics['offline'] == true;
    if (playerController.lyricsMode.toInt() == 1) {
      final plain = playerController.lyrics["plainLyrics"] == "NA"
          ? (offline ? "lyricsOffline" : "lyricsNotAvailable").tr
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
                // Not for the "not available" note.
                translations: playerController.lyrics["plainLyrics"] == "NA"
                    ? null
                    : LyricsTranslation.linesFor(plain.split('\n')),
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
        .bindLyricToMain(
            lyricsReaderLrc(playerController.lyrics['synced'].toString()))
        .getModel();
    // Romanization and translation go in each line's second line.
    final translations = LyricsTranslation.linesFor(
        [for (final line in model.lyrics) line.mainText ?? '']);
    for (var i = 0; i < model.lyrics.length; i++) {
      final line = model.lyrics[i];
      line.extText = lyricsSecondLine(
          LyricsRomanization.lineFor(line.mainText), translations?[i]);
    }
    // TalkBack can't read the lyrics the reader draws: with it on they're
    // text, a line at a time, as Spotify's are.
    if (MediaQuery.accessibleNavigationOf(context) && model.lyrics.isNotEmpty) {
      return ReadableSyncedLyrics(
          lines: model.lyrics, padding: padding, onTap: onTap);
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
            (offline ? "lyricsOffline" : "syncedLyricsNotAvailable").tr,
            style: theme.textTheme.titleMedium!
                .copyWith(color: theme.colorScheme.onSurface),
          ),
        ),
      );
    });
  }
}

/// The spinner while lyrics are looked up, then [loaded]. Outer Obx:
/// loading / mode / lyric payload only — NOT progress ticks ([loaded] is
/// built inside it, so it sees what that reads). The spinner fades in, and
/// lyrics that arrive while it shows fade in over it (lyrics already there
/// when they open just show: their overlay fades in already).
class _LoadingSwap extends StatefulWidget {
  const _LoadingSwap({required this.loaded});
  final Widget Function(BuildContext context) loaded;

  @override
  State<_LoadingSwap> createState() => _LoadingSwapState();
}

class _LoadingSwapState extends State<_LoadingSwap> {
  /// The spinner has shown: what comes next fades in.
  bool _waited = false;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(() {
      if (playerController.isLyricsLoading.isTrue) {
        _waited = true;
        return const RiffFadeIn(
          key: ValueKey<String>('loading'),
          rise: 0,
          child: Center(child: LoadingIndicator()),
        );
      }
      final lyrics = widget.loaded(context);
      if (!_waited) return lyrics;
      return RiffFadeIn(key: const ValueKey<String>('lyrics'), child: lyrics);
    });
  }
}

/// Synced lyrics as text, for TalkBack and other screen readers (the
/// reader paints them, so they can't read it): each line with its
/// romanization or translation under it; a double-tap plays the song from
/// that line, as a tap on a line does in Spotify and Apple Music.
class ReadableSyncedLyrics extends StatelessWidget {
  const ReadableSyncedLyrics(
      {super.key, required this.lines, required this.padding, this.onTap});

  final List<LyricsLineModel> lines;
  final EdgeInsetsGeometry padding;

  /// What a tap on the lyrics' background does (closes them).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    final theme = Theme.of(context);
    final mainStyle = theme.textTheme.titleMedium
        ?.copyWith(color: theme.colorScheme.onSurface);
    final extStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListView.builder(
      padding: padding,
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final start = line.startTime;
        return InkWell(
          onTap: start == null
              ? onTap
              : () {
                  final delay = LyricsTiming.delayMs(
                      playerController.currentSong.value?.id);
                  playerController.seek(Duration(
                      milliseconds: songPositionForLyricMs(start, delay)));
                },
          child: Semantics(
            onTapHint: start == null ? null : 'playFromHere'.tr,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiffSpacing.lg, vertical: RiffSpacing.xs),
              child: Column(
                children: [
                  Text(line.mainText ?? '',
                      style: mainStyle, textAlign: TextAlign.center),
                  if (line.hasExt)
                    Text(line.extText!,
                        style: extStyle, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Plain lyrics as one text, each line followed by its romanization (when
/// [LyricsRomanization] gives one) and its translation (from
/// [translations], one per line), both in [romanStyle].
TextSpan romanizedLyricsText(String lyrics,
    {required TextStyle style,
    required TextStyle romanStyle,
    List<String?>? translations}) {
  final lines = lyrics.split('\n');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < lines.length; i++) ...[
        TextSpan(text: lines[i]),
        if (lyricsSecondLine(
                LyricsRomanization.lineFor(lines[i]),
                translations != null && i < translations.length
                    ? translations[i]
                    : null)
            case final second?)
          TextSpan(text: '\n$second', style: romanStyle),
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
