import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/discovery/discovery_service.dart';
import '/services/not_interested.dart';
import '/ui/player/player_controller.dart';
import 'snackbar.dart';

/// "Not interested", as YouTube Music and Spotify have it for what they
/// pick for you: [song] stays out of radio, Up next, Autoplay and the mixes
/// from now on (you can still play it yourself), its artist comes up a
/// little less, and it goes now: on to the next song when it's the one
/// playing, out of Up Next when it's still to come. Undo (on the snackbar,
/// and returned) takes it back, but for the skip.
Future<VoidCallback> markNotInterested(MediaItem song,
    {BuildContext? context}) async {
  final player = Get.find<PlayerController>();
  final target = undoSnackbarTarget((context != null && context.mounted)
      ? context
      : player.homeScaffoldkey.currentContext ?? Get.context);
  await NotInterested.add(song);
  final discovery = Get.isRegistered<DiscoveryService>()
      ? Get.find<DiscoveryService>()
      : null;
  await discovery?.onNotInterested(song);
  VoidCallback? putBack;
  if (player.currentSong.value?.id == song.id) {
    await player.next();
  } else {
    putBack = await player.removeFromQueueUndoable(song);
  }
  void undo() {
    NotInterested.remove(song.id);
    discovery?.onNotInterested(song, undo: true);
    putBack?.call();
  }

  showUndoSnackbar(target, 'notInterestedDone'.tr, onUndo: undo);
  return undo;
}
