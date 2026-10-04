import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/services/csv_playlist_import.dart';
import '/services/spotify_import_service.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/widgets/snackbar.dart';
import '../screens/Home/home_layout.dart';
import 'common_dialog_widget.dart';

/// Dialog: paste a public Spotify playlist/album URL → resolve on YTM → save
/// as a local Riff playlist (Spotube-style metadata bridge).
class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({super.key, this.initialUrl});

  /// Link to fill in (from the Spotify hub).
  final String? initialUrl;

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  late final _urlController = TextEditingController(text: widget.initialUrl);
  final _busy = false.obs;
  final _status = ''.obs;
  final _progress = 0.0.obs;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _urlController.text = data.text!.trim();
      setState(() {});
    }
  }

  Future<void> _import() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _status.value = 'spotifyImportEnterUrl'.tr;
      return;
    }
    if (SpotifyImportService.parseSpotifyUrl(url) == null) {
      _status.value = 'spotifyImportInvalidUrl'.tr;
      return;
    }

    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService(), permanent: false);
    }
    final svc = Get.find<SpotifyImportService>();

    _busy.value = true;
    _progress.value = 0.05;
    _status.value = 'spotifyImportFetching'.tr;

    try {
      final collection = await svc.fetchPublicCollection(url);
      await _resolveAndSave(
        svc,
        title: '${collection.name} (Spotify)',
        description: 'importedFromSpotify'.tr,
        coverUrl: collection.coverUrl,
        tracks: collection.tracks,
      );
    } catch (e) {
      _fail(e);
    } finally {
      _busy.value = false;
    }
  }

  void _fail(Object e) {
    _status.value = e.toString().replaceFirst('Exception: ', '');
    _progress.value = 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
        context,
        'operationFailed'.tr,
        size: SanckBarSize.MEDIUM,
      ));
    }
  }

  /// A CSV export (Exportify, TuneMyMusic or any title/artist CSV): same
  /// matching as Spotify links, using ISRC codes when the file has them.
  Future<void> _importCsv() async {
    final FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
          type: FileType.any, withData: true, dialogTitle: 'csvImport'.tr);
    } catch (e) {
      _fail(e);
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    if (!Get.isRegistered<SpotifyImportService>()) {
      Get.put(SpotifyImportService(), permanent: false);
    }
    final svc = Get.find<SpotifyImportService>();
    _busy.value = true;
    _progress.value = 0.05;
    _status.value = 'csvImportReading'.tr;
    try {
      final text = f.bytes != null
          ? utf8.decode(f.bytes!, allowMalformed: true)
          : await File(f.path!).readAsString();
      final csv = parsePlaylistCsv(text);
      if (csv.tracks.isEmpty) throw StateError('csvImportEmpty'.tr);
      final fileName = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      await _resolveAndSave(
        svc,
        title: csv.name ?? fileName,
        description: 'importedFromCsv'.trParams({
          'source': switch (csv.format) {
            CsvPlaylistFormat.exportify => 'Exportify',
            CsvPlaylistFormat.tuneMyMusic => 'TuneMyMusic',
            CsvPlaylistFormat.generic => 'CSV',
          }
        }),
        tracks: csv.tracks,
      );
    } on FormatException {
      _fail(StateError('csvImportBadFile'.tr));
    } catch (e) {
      _fail(e);
    } finally {
      _busy.value = false;
    }
  }

  /// Match [tracks] on YouTube Music, save the matches as a local
  /// playlist and show what matched.
  Future<void> _resolveAndSave(
    SpotifyImportService svc, {
    required String title,
    required String description,
    String? coverUrl,
    required List<SpotifyTrackRef> tracks,
  }) async {
    _status.value = '${'spotifyImportResolving'.tr} (${tracks.length})';
    _progress.value = 0.15;

    final resolved = await svc.resolveTracksDetailed(
      tracks,
      onProgress: (done, total) {
        _progress.value = 0.15 + 0.75 * (done / total);
        _status.value = '${'spotifyImportResolving'.tr} $done / $total';
      },
    );
    final items = resolved.whereType<MediaItem>().toList();
    final summary = summarizeImport(tracks, resolved);

    if (items.isEmpty) {
      throw StateError('spotifyImportNoMatches'.tr);
    }

    _status.value = 'spotifyImportSaving'.tr;
    _progress.value = 0.95;

    final playlistId = 'LIBSP${DateTime.now().millisecondsSinceEpoch}';
    final playlist = Playlist(
      title: title,
      playlistId: playlistId,
      thumbnailUrl: coverUrl ??
          items.first.artUri?.toString() ??
          Playlist.thumbPlaceholderUrl,
      description: description,
      isCloudPlaylist: false,
    );

    final plBox = await Hive.openBox('LibraryPlaylists');
    await plBox.put(playlistId, playlist.toJson());

    final songsBox = await Hive.openBox(playlistId);
    for (var i = 0; i < items.length; i++) {
      await songsBox.put(i, MediaItemBuilder.toJson(items[i]));
    }
    await songsBox.close();
    // plBox (LibraryPlaylists) stays open: Hive shares one instance with
    // the library, discovery and the add-to-playlist sheet.

    Get.find<LibraryPlaylistsController>().refreshLib();

    _progress.value = 1.0;
    _status.value =
        '${'spotifyImportDone'.tr} (${summary.matched}/${summary.total})';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => _ImportSummaryDialog(title: title, summary: summary),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title:
          RiffDialogTitle('spotifyImport'.tr, icon: Icons.playlist_add_rounded),
      content: SizedBox(
        width: 420,
        child: Obx(() {
          final busy = _busy.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'spotifyImportDes'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: homeMutedColor(context)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                enabled: !busy,
                decoration: InputDecoration(
                  hintText: 'https://open.spotify.com/playlist/…',
                  filled: true,
                  fillColor: homeTileColor(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'paste'.tr,
                    onPressed: busy ? null : _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste),
                  ),
                ),
                onSubmitted: busy ? null : (_) => _import(),
              ),
              const SizedBox(height: 12),
              if (busy || _progress.value > 0)
                LinearProgressIndicator(
                  value: _progress.value <= 0 || _progress.value >= 1
                      ? null
                      : _progress.value,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: busy ? null : _importCsv,
                  icon: const Icon(Icons.table_view_rounded, size: 20),
                  label: Text('csvImport'.tr),
                ),
              ),
              Text(
                'csvImportDes'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (_status.value.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _status.value,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
              foregroundColor: theme.textTheme.titleMedium?.color),
          child: Text('cancel'.tr),
        ),
        Obx(() => FilledButton.icon(
              onPressed: _busy.value ? null : _import,
              icon: _busy.value
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: theme.colorScheme.onPrimary),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text('import'.tr),
            )),
      ],
    );
  }
}

/// "Matched 47 of 50", with the tracks that didn't match.
class _ImportSummaryDialog extends StatelessWidget {
  const _ImportSummaryDialog({required this.title, required this.summary});
  final String title;
  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: RiffDialogTitle(title,
          icon: Icons.playlist_add_check_rounded,
          subtitle: 'importMatched'.trParams({
            'matched': '${summary.matched}',
            'total': '${summary.total}',
          })),
      content: SizedBox(
        width: 420,
        child: summary.unmatched.isEmpty
            ? Text('importAllMatched'.tr,
                textAlign: TextAlign.center,
                style: homeCardSubtitleStyle(context))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('importUnmatched'
                      .trParams({'count': '${summary.unmatched.length}'})),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in summary.unmatched)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child:
                                Text(u, style: homeCardSubtitleStyle(context)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('done'.tr),
        ),
      ],
    );
  }
}
