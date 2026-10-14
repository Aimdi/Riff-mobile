import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/playling_from.dart';
import '../models/playlist.dart';
import '/services/app_shortcuts.dart';
import '/ui/screens/Search/components/search_pill.dart';
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
    // After the first frame: the labels need the app's translations.
    WidgetsBinding.instance.addPostFrameCallback((_) => AppShortcuts.publish());
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
    // A long-press shortcut on the app icon.
    final shortcut = AppShortcut.fromUri(uri);
    if (shortcut != null) return openAppShortcut(shortcut);
    // "Play … on Riff" from the Assistant.
    final voice = voiceSearchQuery(uri);
    if (voice != null) return playVoiceSearch(voice);

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

  /// A voice request plays as it does in Android Auto
  /// ([PlayerController.playFromVoiceSearch]). It can also start the app,
  /// so this waits (a few seconds at most) for the player.
  Future<void> playVoiceSearch(String query) async {
    for (var i = 0; i < 50 && !Get.isRegistered<PlayerController>(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!Get.isRegistered<PlayerController>()) return;
    await Get.find<PlayerController>().playFromVoiceSearch(query);
  }

  /// The page an app icon shortcut names. A shortcut can also start the
  /// app, so this waits (a few seconds at most) for its pages to be up.
  Future<void> openAppShortcut(AppShortcut shortcut) async {
    final pages = Get.nestedKey(ScreenNavigationSetup.id);
    for (var i = 0; i < 50 && pages?.currentState == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (pages?.currentState == null) return;
    try {
      final panel = Get.find<PlayerController>().playerPanelController;
      if (panel.isPanelOpen) panel.close();
    } catch (_) {
      // The player isn't laid out yet: nothing to close.
    }
    switch (shortcut) {
      case AppShortcut.search:
        SearchLauncherField.openSearch();
      case AppShortcut.liked:
        _openLibraryPlaylist('LIBFAV', 'favorites'.tr);
      case AppShortcut.downloads:
        _openLibraryPlaylist('SongDownloads', 'downloads'.tr);
    }
  }

  void _openLibraryPlaylist(String id, String title) => Get.toNamed(
        ScreenNavigationSetup.playlistScreen,
        id: ScreenNavigationSetup.id,
        arguments: [
          Playlist(
              title: title,
              playlistId: id,
              thumbnailUrl: Playlist.thumbPlaceholderUrl,
              isCloudPlaylist: false),
          id,
        ],
      );

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
