// ignore_for_file: constant_identifier_names

import 'package:get/get.dart';

class PlaylingFrom {
  PlaylingFromType type;
  String name;

  /// Browse id of the album, playlist or artist playback came from, so the
  /// player's "Playing from" header can open it; empty when there is none.
  String id;

  /// The Album / Playlist model when the caller has it, so the page opens
  /// with its header already filled in.
  Object? item;

  PlaylingFrom({required this.type, this.name = "", this.id = "", this.item});

  /// Whether the "Playing from" header can open where playback came from.
  bool get canOpen => id.isNotEmpty && type != PlaylingFromType.SELECTION;

  get typeString {
    switch (type) {
      case PlaylingFromType.ALBUM:
        return "playingfromAlbum".tr;
      case PlaylingFromType.PLAYLIST:
        return "playingfromPlaylist".tr;
      case PlaylingFromType.SELECTION:
        return "playingfromSelection".tr;
      case PlaylingFromType.ARTIST:
        return "playingfromArtist".tr;
    }
  }

  get nameString {
    if (type == PlaylingFromType.SELECTION) {
      return name.isNotEmpty ? name : "randomSelection".tr;
    }
    return name;
  }
}

enum PlaylingFromType { ALBUM, PLAYLIST, SELECTION, ARTIST }
