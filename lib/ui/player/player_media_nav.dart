import 'package:get/get.dart';

import '../navigator.dart';
import 'player_controller.dart';
import 'player_media_ids.dart';

export 'player_media_ids.dart';

/// Open the album/single of the currently-playing song (no-op when the track
/// carries no album, e.g. a podcast episode).
void openCurrentAlbum(PlayerController playerController) {
  final albumId = songAlbumId(playerController.currentSong.value);
  if (albumId == null) return;
  playerController.playerPanelController.close();
  Get.toNamed(ScreenNavigationSetup.albumScreen,
      id: ScreenNavigationSetup.id, arguments: (null, albumId));
}

/// Open the artist page for the currently-playing song. Uses extras.artistId
/// or the first artist that has a browse id (no-op when none is available).
void openCurrentArtist(PlayerController playerController) {
  final artistId = songArtistId(playerController.currentSong.value);
  if (artistId == null) return;
  playerController.playerPanelController.close();
  Get.toNamed(ScreenNavigationSetup.artistScreen,
      id: ScreenNavigationSetup.id,
      preventDuplicates: true,
      arguments: [true, artistId]);
}
