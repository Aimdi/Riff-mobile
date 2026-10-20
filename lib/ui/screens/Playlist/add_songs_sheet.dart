import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/music_service.dart';
import '/ui/screens/Audiobooks/audiobook_widgets.dart'
    show AudiobookSearchField;
import '/ui/theme/riff_spacing.dart';
import '/ui/theme/riff_tokens.dart';
import '/ui/widgets/image_widget.dart';
import '/ui/widgets/riff_motion.dart';
import '/ui/widgets/riff_sheet.dart';
import 'playlist_screen_controller.dart';

/// The songs YouTube Music finds for [query].
Future<List<MediaItem>> searchSongsToAdd(String query) async {
  final found = await Get.find<MusicServices>().search(query, filter: 'songs');
  final songs = found['Songs'];
  return songs is List ? songs.whereType<MediaItem>().toList() : const [];
}

/// One of your playlists' ⋮ › Add songs.
Future<void> showAddSongsSheet(
        BuildContext context, PlaylistScreenController controller) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      constraints:
          const BoxConstraints(maxWidth: RiffComponentSizes.sheetMaxWidth),
      shape: riffSheetShape,
      builder: (_) => AddSongsSheet(controller: controller),
    );

/// Spotify's "Add to this playlist": search for songs and add them to the
/// playlist with + without leaving it; the ones in it already have a check.
class AddSongsSheet extends StatefulWidget {
  const AddSongsSheet({super.key, required this.controller});

  final PlaylistScreenController controller;

  @override
  State<AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends State<AddSongsSheet> {
  final _query = TextEditingController();
  Future<List<MediaItem>>? _results;
  Timer? _typing;
  String _searched = '';

  /// In the playlist, before or since the sheet opened.
  late final Set<String> _inPlaylist = {
    for (final s in widget.controller.tempListContainer.isNotEmpty
        ? widget.controller.tempListContainer
        : widget.controller.songList)
      s.id
  };

  @override
  void initState() {
    super.initState();
    _query.addListener(_onTyping);
  }

  /// Searches once typing pauses (as the search screen's suggestions).
  void _onTyping() {
    if (_query.text.trim() == _searched) return;
    _typing?.cancel();
    _typing = Timer(RiffDurations.typingPause, () => _search(_query.text));
  }

  void _search(String text) {
    _typing?.cancel();
    final query = text.trim();
    if (query == _searched || !mounted) return;
    setState(() {
      _searched = query;
      _results = query.isEmpty ? null : searchSongsToAdd(query);
    });
  }

  Future<void> _add(MediaItem song) async {
    setState(() {
      _inPlaylist.add(song.id);
    });
    await widget.controller.appendSong(song);
  }

  @override
  void dispose() {
    _typing?.cancel();
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
            RiffSheetTitle('addSongs'.tr,
                subtitle: widget.controller.playlist.value.title),
            AudiobookSearchField(
              controller: _query,
              hint: 'searchSongsToAdd'.tr,
              autofocus: true,
              onSubmitted: _search,
            ),
            Expanded(
              child: _results == null
                  ? _message(context, 'addSongsHint'.tr)
                  : FutureBuilder<List<MediaItem>>(
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
                                    strokeWidth:
                                        RiffComponentSizes.spinnerStroke),
                              ),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return _message(context, 'networkError'.tr);
                        }
                        final found = snap.data ?? const <MediaItem>[];
                        if (found.isEmpty) {
                          return _message(context, 'noSongsFound'.tr);
                        }
                        // Results fade in where the spinner was.
                        return RiffFadeIn(
                          child: ListView.builder(
                            controller: scroll,
                            padding: const EdgeInsets.only(
                                bottom: RiffSpacing.listEnd),
                            itemCount: found.length,
                            itemBuilder: (_, i) => _SongToAdd(
                              song: found[i],
                              added: _inPlaylist.contains(found[i].id),
                              onAdd: () => _add(found[i]),
                            ),
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

/// A song found: its cover, title and artist, and + (a check once it's in
/// the playlist).
class _SongToAdd extends StatelessWidget {
  const _SongToAdd(
      {required this.song, required this.added, required this.onAdd});

  final MediaItem song;
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      leading: ImageWidget(song: song, size: RiffComponentSizes.miniArt),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
      // Adding it pops the check in.
      trailing: RiffSwitcher(
        pop: added,
        child: added
            ? Padding(
                key: const ValueKey(true),
                padding: const EdgeInsets.all(RiffSpacing.md),
                child: Icon(Icons.check_circle_rounded,
                    size: RiffComponentSizes.trailingIcon,
                    color: theme.colorScheme.primary,
                    semanticLabel: 'alreadyInPlaylist'.tr),
              )
            : IconButton(
                key: const ValueKey(false),
                tooltip: 'addToPlaylist'.tr,
                onPressed: onAdd,
                icon: Icon(Icons.add_circle_outline_rounded,
                    size: RiffComponentSizes.trailingIcon, color: muted),
              ),
      ),
    );
  }
}
