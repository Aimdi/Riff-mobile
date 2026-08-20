import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';

import '/models/playling_from.dart';
import '/services/discovery/discovery_types.dart';
import '/services/soulseek/soulseek_client.dart';
import '/ui/player/player_controller.dart';

/// Search rows download and play; the trailing button still downloads only.
bool shouldPlaySoulseekOnTap() => true;

/// Stable player id so a local Soulseek file is not sent to YouTube.
String soulseekMediaId({
  required String username,
  required String filename,
}) {
  final raw = '$username|$filename';
  final safe = Uri.encodeComponent(raw);
  if (safe.length <= 160) return 'slsk_$safe';
  var h = 0;
  for (final c in raw.codeUnits) {
    h = (h * 33 + c) & 0x7fffffff;
  }
  return 'slsk_${safe.substring(0, 120)}_$h';
}

MediaItem soulseekFileToMediaItem(
  SoulseekFile hit, {
  String? filePath,
  String? artist,
}) {
  final title = hit.displayName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final who = artist ??
      (hit.folderName.isNotEmpty ? hit.folderName : hit.username);
  final path = filePath;
  final url = path == null
      ? null
      : path.startsWith('file://')
          ? path
          : 'file://$path';
  return MediaItem(
    id: soulseekMediaId(username: hit.username, filename: hit.filename),
    title: title.isEmpty ? hit.displayName : title,
    artist: who,
    album: hit.folderName.isEmpty ? null : hit.folderName,
    duration: hit.lengthSeconds != null && hit.lengthSeconds! > 0
        ? Duration(seconds: hit.lengthSeconds!)
        : null,
    extras: {
      if (url != null) 'url': url,
      'streamSource': 'soulseek',
      'artists': [
        {'name': who, 'id': null}
      ],
      'album': hit.folderName.isEmpty ? null : {'name': hit.folderName},
      'length': hit.lengthLabel,
    },
  );
}

/// Play a downloaded Soulseek file through the existing local-url path.
Future<bool> playSoulseekFile(SoulseekFile hit, File file) async {
  if (!Get.isRegistered<PlayerController>()) return false;
  if (!file.existsSync()) return false;
  final item = soulseekFileToMediaItem(hit, filePath: file.path);
  return Get.find<PlayerController>().playPlayListSong(
    [item],
    0,
    playfrom: PlaylingFrom(
      type: PlaylingFromType.SELECTION,
      name: item.title,
    ),
    source: DiscoverySource.soulseek,
  );
}
