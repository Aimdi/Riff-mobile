import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '/services/better_lyrics_service.dart';
import '/ui/player/player_controller.dart';
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/riff_sheet.dart';
import '/ui/widgets/snackbar.dart';
import 'cover_palette.dart';

/// Most lines one card holds, as in Spotify.
const maxSharedLyricLines = 5;

final _lrcTime = RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]');
final _lrcTag = RegExp(r'^\[[A-Za-z]+:.*\]$');

/// The lines a song's lyrics can be shared from: word-synced (TTML) first,
/// then line-synced (LRC, without its times and tags), then plain lyrics
/// ("NA" when there are none).
List<String> lyricLinesForSharing(
    {String? ttml, String? synced, String? plain}) {
  final fromTtml = (ttml ?? '').trim().isEmpty
      ? null
      : BetterLyricsService.ttmlToPlain(ttml!);
  final String text;
  if (fromTtml != null && fromTtml.trim().isNotEmpty) {
    text = fromTtml;
  } else if ((synced ?? '').trim().isNotEmpty) {
    text = synced!
        .split('\n')
        .where((l) => !_lrcTag.hasMatch(l.trim()))
        .map((l) => l.replaceAll(_lrcTime, ''))
        .join('\n');
  } else if (plain != null && plain.trim().isNotEmpty && plain != 'NA') {
    text = plain;
  } else {
    return const [];
  }
  return [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
}

/// The playing song's lyrics as a card to share, like Spotify's and Apple
/// Music's: pick up to [maxSharedLyricLines] lines, see the card, share it
/// as an image. Says so when the song has no lyrics.
Future<void> showLyricsShareSheet(BuildContext? context) async {
  if (!Get.isRegistered<PlayerController>()) return;
  final pc = Get.find<PlayerController>();
  final song = pc.currentSong.value;
  final ctx = (context != null && context.mounted) ? context : Get.context;
  if (song == null || ctx == null) return;
  final target = undoSnackbarTarget(ctx);
  await pc.prefetchLyrics();
  final lines = lyricLinesForSharing(
    ttml: pc.lyrics['ttml']?.toString(),
    synced: pc.lyrics['synced']?.toString(),
    plain: pc.lyrics['plainLyrics']?.toString(),
  );
  if (lines.isEmpty || !ctx.mounted) {
    showUndoSnackbar(target, 'lyricsNotAvailable'.tr);
    return;
  }
  await showModalBottomSheet<void>(
    context: ctx,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => LyricsShareSheet(song: song, lines: lines),
  );
}

/// The image a lyrics share sends: the cover's colours (white text always
/// reads on them), the song at the top, the picked lines large.
class LyricsShareCard extends StatelessWidget {
  const LyricsShareCard(
      {super.key,
      required this.song,
      required this.lines,
      required this.palette});

  final MediaItem song;
  final List<String> lines;
  final CoverPalette palette;

  /// Laid out this wide; shared [imageWidth] pixels wide.
  static const double width = 320;
  static const double imageWidth = 1080;

  /// Strength of the artist and the wordmark under the white text.
  static const double _secondaryOpacity = 0.72;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const fg = RiffPalette.onImage;
    final muted = fg.withOpacity(_secondaryOpacity);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
          horizontal: RiffSpacing.xl, vertical: RiffSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RiffRadii.lg),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.fill, palette.deep],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ImageWidget(
                  song: song,
                  size: RiffComponentSizes.rowArt,
                  borderRadius: RiffRadii.xs),
              const SizedBox(width: RiffSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(color: fg)),
                    Text(song.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: RiffSpacing.xl),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: RiffSpacing.xs),
              child: Text(line, style: text.headlineSmall?.copyWith(color: fg)),
            ),
          const SizedBox(height: RiffSpacing.lg),
          Text('Riff', style: text.labelMedium?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

/// Lines to pick from, the card as it will look, and Share.
class LyricsShareSheet extends StatefulWidget {
  const LyricsShareSheet({super.key, required this.song, required this.lines});

  final MediaItem song;
  final List<String> lines;

  @override
  State<LyricsShareSheet> createState() => _LyricsShareSheetState();
}

class _LyricsShareSheetState extends State<LyricsShareSheet> {
  final _card = GlobalKey();

  /// Starts with the first line, so the card is never empty.
  final _picked = <int>{0};
  bool _sharing = false;

  /// Most of the sheet the card preview may take.
  static const double _previewShare = 0.36;

  List<String> get _pickedLines => [
        for (var i = 0; i < widget.lines.length; i++)
          if (_picked.contains(i)) widget.lines[i],
      ];

  void _toggle(int i) => setState(() {
        if (!_picked.remove(i) && _picked.length < maxSharedLyricLines) {
          _picked.add(i);
        }
      });

  Future<void> _share() async {
    final boundary = _card.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    final target = undoSnackbarTarget(context);
    setState(() => _sharing = true);
    try {
      final image = await boundary.toImage(
          pixelRatio: LyricsShareCard.imageWidth / LyricsShareCard.width);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) throw StateError('no image');
      final file =
          File('${(await getTemporaryDirectory()).path}/riff-lyrics.png');
      await file.writeAsBytes(png.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'riff-lyrics.png')],
        text: [widget.song.title, widget.song.artist ?? '']
            .where((s) => s.isNotEmpty)
            .join(' · '),
      );
    } catch (_) {
      showUndoSnackbar(target, 'operationFailed'.tr);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scroll) => Obx(() {
        // Reactive: the cover's colours may arrive after the sheet opens.
        final palette = PlayerCoverColors.of(widget.song) ??
            coverPaletteFrom(dominant: accent);
        return Column(
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('shareLyrics'.tr,
                subtitle: 'pickLyricLines'
                    .trParams({'count': '$maxSharedLyricLines'})),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: RiffSpacing.xl, vertical: RiffSpacing.sm),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight:
                        MediaQuery.sizeOf(context).height * _previewShare),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _card,
                    child: LyricsShareCard(
                        song: widget.song,
                        lines: _pickedLines,
                        palette: palette),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: widget.lines.length,
                itemBuilder: (context, i) {
                  final picked = _picked.contains(i);
                  return Semantics(
                    selected: picked,
                    button: true,
                    child: InkWell(
                      onTap: () => _toggle(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: RiffSpacing.xl,
                            vertical: RiffSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.lines[i],
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: picked
                                        ? accent
                                        : theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                            if (picked)
                              Icon(Icons.check_rounded,
                                  color: accent,
                                  size: RiffComponentSizes.trailingIcon),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: RiffSpacing.xl, vertical: RiffSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _picked.isEmpty || _sharing ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text('share'.tr),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
