import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/lyrics_search.dart';
import '/ui/screens/Audiobooks/audiobook_widgets.dart'
    show AudiobookSearchField;
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/riff_sheet.dart';
import '../player_controller.dart';

/// ⋮ › Search lyrics, for the song playing.
Future<void> showLyricsSearchSheet(BuildContext? context) async {
  final song = Get.find<PlayerController>().currentSong.value;
  if (context == null || !context.mounted || song == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    constraints:
        const BoxConstraints(maxWidth: RiffComponentSizes.sheetMaxWidth),
    shape: riffSheetShape,
    builder: (_) => LyricsSearchSheet(song: song),
  );
}

/// LRCLIB's lyrics for words you can change (the song's title and artist
/// to begin with), synced ones first, as Metrolist's lyrics search: tap
/// one and it's the song's lyrics.
class LyricsSearchSheet extends StatefulWidget {
  const LyricsSearchSheet({super.key, required this.song});

  final MediaItem song;

  @override
  State<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends State<LyricsSearchSheet> {
  late final _query =
      TextEditingController(text: lyricsSearchQuery(widget.song));
  late Future<List<LyricsCandidate>> _results = _search();

  Future<List<LyricsCandidate>> _search() =>
      LyricsSearch.search(_query.text.trim(), widget.song);

  void _submit(String _) {
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _results = _search();
    });
  }

  Future<void> _pick(LyricsCandidate picked) async {
    await LyricsSearch.choose(widget.song, picked);
    if (Get.isRegistered<PlayerController>()) {
      Get.find<PlayerController>().useLyrics(widget.song, picked.cacheEntry);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _message(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(RiffSpacing.x3l),
      child: Text(text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Above the keyboard while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: RiffComponentSizes.listSheetStart,
        maxChildSize: RiffComponentSizes.listSheetMax,
        builder: (context, scroll) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RiffSheetHandle(),
            RiffSheetTitle('searchLyrics'.tr, subtitle: widget.song.title),
            AudiobookSearchField(
              controller: _query,
              hint: 'searchLyricsHint'.tr,
              onSubmitted: _submit,
            ),
            Expanded(
              child: FutureBuilder<List<LyricsCandidate>>(
                future: _results,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.all(RiffSpacing.x3l),
                        child: SizedBox.square(
                          dimension: RiffComponentSizes.spinner,
                          child: CircularProgressIndicator(
                              strokeWidth: RiffComponentSizes.spinnerStroke),
                        ),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return _message(context, 'lyricsSearchFailed'.tr);
                  }
                  final found = snap.data ?? const <LyricsCandidate>[];
                  if (found.isEmpty) {
                    return _message(context, 'noLyricsFound'.tr);
                  }
                  return ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.only(bottom: RiffSpacing.listEnd),
                    itemCount: found.length,
                    itemBuilder: (_, i) => _CandidateTile(
                      candidate: found[i],
                      onTap: () => _pick(found[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A result: the track, its artist, album and length, and whether its
/// lyrics are synced.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.onTap});

  final LyricsCandidate candidate;
  final VoidCallback onTap;

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = candidate;
    final details = [
      c.artist,
      if (c.album != null) c.album!,
      if (c.durationSec != null) _clock(c.durationSec!),
    ].where((part) => part.isNotEmpty).join(' · ');
    return ListTile(
      onTap: onTap,
      leading: Icon(c.isSynced ? Icons.lyrics_outlined : Icons.notes_rounded,
          color: muted),
      title: Text(c.track, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
      trailing: Text((c.isSynced ? 'lyricsSynced' : 'lyricsPlain').tr,
          style: theme.textTheme.labelSmall?.copyWith(color: muted)),
    );
  }
}
