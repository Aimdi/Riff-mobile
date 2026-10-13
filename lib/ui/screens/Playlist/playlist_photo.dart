import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '/services/playlist_covers.dart';
import '/ui/widgets/snackbar.dart';

/// Pick a photo for one of your playlists, like Spotify's "Change image":
/// it is cropped to a square, shrunk and kept ([PlaylistCovers]), and the
/// playlist shows it wherever its cover shows.
Future<void> pickPlaylistPhoto(BuildContext context, String playlistId) async {
  final res = await FilePicker.platform
      .pickFiles(type: FileType.image, withData: false);
  final file = res?.files.firstOrNull;
  if (file == null) return;
  Uint8List? bytes = file.bytes;
  final path = file.path;
  if (bytes == null && path != null) {
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {}
  }
  final ok = bytes != null && await PlaylistCovers.set(playlistId, bytes);
  if (!ok && context.mounted) snackOperationFailed(context);
}
