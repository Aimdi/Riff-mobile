/// The music files on the phone, as Spotify's Local files and YouTube
/// Music's Device files: the Songs library's "On this phone" (Android).
/// MediaStore lists them (DeviceMusic.kt); each plays straight from its
/// file (its content:// address), as a song with an address of its own
/// does (ids device_…), so it plays offline too.
library;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '/native_bindings/andrid_utils.dart' show SDKInt;
import '/utils/helper.dart';

class DeviceMusic {
  DeviceMusic._();

  static const channel = MethodChannel('riff/device_music');

  /// What the phone's songs' ids start with.
  static const idPrefix = 'device_';

  static bool get available => defaultTargetPlatform == TargetPlatform.android;

  /// Android's version; tests set it.
  @visibleForTesting
  static int Function() sdkInt = () => SDKInt.Companion.getSDKInt();

  /// Where the albums' covers are kept; tests set it.
  @visibleForTesting
  static Future<String> Function() coverFolder =
      () async => '${(await getApplicationSupportDirectory()).path}/device_art';

  /// Reading music files: READ_MEDIA_AUDIO from Android 13, storage before.
  static Permission get _permission =>
      sdkInt() >= 33 ? Permission.audio : Permission.storage;

  /// Android's permission to read the phone's music, asked for (false
  /// when refused). Refused for good, [settings] opens Riff's app
  /// settings, where it can still be given.
  static Future<bool> askAccess({bool settings = false}) async {
    if (!available) return false;
    try {
      final status = await _permission.request();
      if (status.isGranted || status.isLimited) return true;
      if (settings && status.isPermanentlyDenied) await openAppSettings();
      return false;
    } catch (e) {
      printERROR('Music files permission: $e');
      return false;
    }
  }

  /// The phone's songs, by title; null when they can't be listed (no
  /// permission to).
  static Future<List<MediaItem>?> songs() async {
    if (!available) return const [];
    try {
      final raw = await channel.invokeListMethod<Map<Object?, Object?>>(
          'songs', {'artDir': await coverFolder()});
      if (raw == null) return null;
      return raw
          .map((m) => deviceSong(Map<String, dynamic>.from(m)))
          .whereType<MediaItem>()
          .toList();
    } catch (e) {
      printERROR('Music files: $e');
      return null;
    }
  }

  static bool isDeviceSong(MediaItem song) => song.id.startsWith(idPrefix);

  /// [length] bytes of the music file at [uri] (its content:// address)
  /// from [offset], fewer at its end: its tags, for the lyrics in them.
  /// Null when it can't be read.
  static Future<Uint8List?> read(String uri, int offset, int length) async {
    if (!available) return null;
    try {
      return await channel.invokeMethod<Uint8List>(
          'read', {'uri': uri, 'offset': offset, 'length': length});
    } catch (e) {
      printERROR('Music file read: $e');
      return null;
    }
  }
}

/// One of MediaStore's songs ([DeviceMusic.songs]) as Riff plays it: its
/// file's address to play and its album's cover, kept through playlists
/// and the saved queue (url, artists, a file:// cover). Null without an
/// address to play.
MediaItem? deviceSong(Map<String, dynamic> song) {
  String? text(String key) {
    final value = '${song[key] ?? ''}'.trim();
    // MediaStore's word for a tag that isn't there.
    return value.isEmpty || value == '<unknown>' ? null : value;
  }

  final id = text('id');
  final uri = text('uri');
  if (id == null || uri == null || !uri.startsWith('content://')) return null;
  final artist = text('artist');
  final art = text('art');
  final ms = song['durationMs'];
  final addedSec = song['addedSec'];
  final track = song['track'];
  final albumId = text('albumId');
  return MediaItem(
    id: '${DeviceMusic.idPrefix}$id',
    title: text('title') ?? '',
    artist: artist,
    album: text('album'),
    duration: ms is int && ms > 0 ? Duration(milliseconds: ms) : null,
    artUri: art == null ? null : Uri.file(art),
    extras: {
      'url': uri,
      // When it came onto the phone, for Songs' Date added sort.
      if (addedSec is int && addedSec > 0) 'date': addedSec * 1000,
      // Its album and number on it (MediaStore's, the disc in thousands),
      // for an album played and sorted in order.
      if (albumId != null) 'albumId': albumId,
      if (track is int && track > 0) 'trackDetails': '$track',
      if (artist != null)
        'artists': [
          {'name': artist},
        ],
    },
  );
}
