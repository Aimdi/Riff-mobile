import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/services/spotify_import_service.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/widgets/snackbar.dart';

/// Dialog: paste a public Spotify playlist/album URL → resolve on YTM → save
/// as a local Riff playlist (Spotube-style metadata bridge).
class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({super.key});

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  final _urlController = TextEditingController();
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
      _status.value =
          '${'spotifyImportResolving'.tr} (${collection.tracks.length})';
      _progress.value = 0.15;

      final items = await svc.resolveTracksToYtm(
        collection.tracks,
        onProgress: (done, total) {
          _progress.value = 0.15 + 0.75 * (done / total);
          _status.value =
              '${'spotifyImportResolving'.tr} $done / $total';
        },
      );

      if (items.isEmpty) {
        throw StateError('spotifyImportNoMatches'.tr);
      }

      _status.value = 'spotifyImportSaving'.tr;
      _progress.value = 0.95;

      final playlistId = 'LIBSP${DateTime.now().millisecondsSinceEpoch}';
      final playlist = Playlist(
        title: '${collection.name} (Spotify)',
        playlistId: playlistId,
        thumbnailUrl: collection.coverUrl ??
            items.first.artUri?.toString() ??
            Playlist.thumbPlaceholderUrl,
        description: 'importedFromSpotify'.tr,
        isCloudPlaylist: false,
      );

      final plBox = await Hive.openBox('LibraryPlaylists');
      await plBox.put(playlistId, playlist.toJson());

      final songsBox = await Hive.openBox(playlistId);
      for (var i = 0; i < items.length; i++) {
        await songsBox.put(i, MediaItemBuilder.toJson(items[i]));
      }
      await songsBox.close();
      await plBox.close();

      Get.find<LibraryPlaylistsController>().refreshLib();

      _progress.value = 1.0;
      _status.value =
          '${'spotifyImportDone'.tr} (${items.length}/${collection.tracks.length})';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context,
          '${playlist.title}: ${items.length} ${'songs'.tr}',
          size: SanckBarSize.MEDIUM,
        ));
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      _status.value = e.toString().replaceFirst('Exception: ', '');
      _progress.value = 0;
    } finally {
      _busy.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Text('spotifyImport'.tr, style: theme.textTheme.titleLarge),
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
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                enabled: !busy,
                decoration: InputDecoration(
                  hintText: 'https://open.spotify.com/playlist/…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
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
          child: Text('cancel'.tr),
        ),
        Obx(() => ElevatedButton.icon(
              onPressed: _busy.value ? null : _import,
              icon: _busy.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text('import'.tr),
            )),
      ],
    );
  }
}
