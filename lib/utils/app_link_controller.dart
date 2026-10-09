import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/playling_from.dart';
import '/ui/widgets/songinfo_bottom_sheet.dart';
import '/utils/helper.dart';
import '../ui/widgets/loader.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '../ui/navigator.dart';
import '../ui/widgets/snackbar.dart';

class AppLinksController extends GetxController with ProcessLink {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void onInit() {
    initDeepLinks();
    super.onInit();
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was in cold state (terminated). A failure
    // here (e.g. the player panel not laid out yet) used to throw past the
    // subscription below, so no shared link opened for the whole session.
    try {
      final appLink = await _appLinks.getInitialAppLink();
      if (appLink != null) {
        await filterLinks(appLink);
      }
    } catch (e) {
      printERROR('Opening the launch link failed: $e');
    }

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      try {
        await filterLinks(uri);
      } catch (e) {
        printERROR('Opening link $uri failed: $e');
      }
    });
  }

  // GetX calls onClose when the controller is deleted; the dispose()
  // override this replaces was never called, so the subscription leaked.
  @override
  void onClose() {
    _linkSubscription?.cancel();
    super.onClose();
  }
}

mixin ProcessLink {
  Future<void> filterLinks(Uri uri) async {
    final playerController = Get.find<PlayerController>();
    if (playerController.playerPanelController.isPanelOpen) {
      playerController.playerPanelController.close();
    }

    if (Get.isRegistered<SongInfoController>()) {
      Navigator.of(Get.context!).pop();
    }

    if (uri.host == "youtube.com" ||
        uri.host == "music.youtube.com" ||
        uri.host == "youtu.be" ||
        uri.host == "www.youtube.com" ||
        uri.host == "m.youtube.com") {
      printINFO(
          "pathsegmet: ${uri.pathSegments} params:${uri.queryParameters}");
      // A bare host (music.youtube.com) or a link missing its id is not
      // something to open; say so instead of throwing.
      final segs = uri.pathSegments;
      final first = segs.isEmpty ? '' : segs[0];
      final videoId = uri.queryParameters['v'] ?? '';
      final listId = uri.queryParameters['list'] ?? '';
      if (first.isEmpty ||
          (first == "watch" && videoId.isEmpty) ||
          (first == "channel" && segs.length < 2) ||
          (first == "playlist" && listId.isEmpty)) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "notaValidLink".tr,
            size: SanckBarSize.MEDIUM));
        return;
      }
      if (first == "playlist") {
        await openPlaylistOrAlbum(listId);
      } else if (first == "shorts") {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "notaSongVideo".tr,
            size: SanckBarSize.MEDIUM));
      } else if (first == "watch") {
        await playSong(videoId);
      } else if (first == "channel") {
        await openArtist(segs[1]);
      } else if ((uri.queryParameters.isEmpty || uri.query.contains("si=")) &&
          uri.host == "youtu.be") {
        await playSong(first);
      }
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaValidLink".tr,
          size: SanckBarSize.MEDIUM));
    }
  }

  Future<void> openPlaylistOrAlbum(String browseId) async {
    if (browseId.contains("OLAK5uy")) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (null, browseId));
    } else {
      Get.toNamed(ScreenNavigationSetup.playlistScreen,
          id: ScreenNavigationSetup.id, arguments: [null, browseId]);
    }
  }

  Future<void> openArtist(String channelId) async {
    await Get.toNamed(ScreenNavigationSetup.artistScreen,
        id: ScreenNavigationSetup.id, arguments: [true, channelId]);
  }

  Future<void> playSong(String songId) async {
    final ctx = Get.context!;
    // The spinner's own route, so closing it can never pop something else.
    final spinner = DialogRoute<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => const Center(
                child: LoadingIndicator(
              strokeWidth: 5,
            )));
    Navigator.of(ctx).push(spinner);
    List result;
    try {
      result = await Get.find<MusicServices>().getSongWithId(songId);
    } catch (e) {
      // Offline, or the video is unavailable / region-blocked.
      printERROR('Shared link $songId failed: $e');
      result = [false];
    } finally {
      if (spinner.isActive) spinner.navigator?.removeRoute(spinner);
    }
    if (result[0] == true) {
      final ok = await Get.find<PlayerController>().playPlayListSong(
          List.from(result[1]), 0,
          playfrom: PlaylingFrom(type: PlaylingFromType.SELECTION));
      if (!ok) snackOperationFailed();
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaSongVideo".tr,
          size: SanckBarSize.MEDIUM));
    }
  }
}
