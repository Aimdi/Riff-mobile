import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '/models/media_item_extras.dart';
import '/services/collection_recents.dart';
import '/services/diag_log.dart';
import '/ui/widgets/sort_widget.dart';
import 'app_version.dart';

void printERROR(dynamic text, {String tag = "Harmony Music"}) {
  DiagLog.add('E $text');
  if (kReleaseMode) return;
  debugPrint("\x1B[31m[$tag]: $text\x1B[0m");
}

void printWarning(dynamic text, {String tag = 'Harmony Music'}) {
  DiagLog.add('W $text');
  if (kReleaseMode) return;
  debugPrint("\x1B[33m[$tag]: $text\x1B[34m");
}

void printINFO(dynamic text, {String tag = 'Harmony Music'}) {
  DiagLog.add('I $text');
  if (kReleaseMode) return;
  debugPrint("\x1B[32m[$tag]: $text\x1B[34m");
}

void sortSongsNVideos(
  List songlist,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction = (a, b) {
        if (a.extras!['date'] == null || b.extras!['date'] == null) {
          return 0.compareTo(0);
        }
        return a.extras!['date'].compareTo(b.extras!['date']);
      };
      break;
    case SortType.Duration:
      compareFunction = (a, b) =>
          (a.duration ?? Duration.zero).compareTo(b.duration ?? Duration.zero);
    // Grouped, then by album / artist and title within the group.
    case SortType.Artist:
      compareFunction = (a, b) => _compareSongsBy(
          a, b, [(s) => s.artist, _songAlbumName, (s) => s.title]);
    // An album's numbered tracks in their order, as Spotify and Apple
    // Music list them (each album of a name on its own); the rest after,
    // by artist and title.
    case SortType.Album:
      compareFunction = (a, b) => _compareSongsBy(a, b, [
            _songAlbumName,
            (s) => s is MediaItem && s.albumTrackNumber != null
                ? s.albumKey
                : null,
            (s) => s is MediaItem
                ? s.albumTrackNumber?.toString().padLeft(9, '0')
                : null,
            (s) => s.artist,
            (s) => s.title
          ]);
    case SortType.Name:
    default:
      compareFunction =
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
  }

  songlist.sort(compareFunction);

  if (!isAscending) {
    List reversed = songlist.reversed.toList();
    songlist.clear();
    songlist.addAll(reversed);
  }
}

/// A song's album name: the album map YouTube gives, else the plain field.
String? _songAlbumName(dynamic song) {
  final album = song.extras?['album'];
  if (album is Map && album['name'] != null) return '${album['name']}';
  return song.album;
}

/// An album's (first) artist.
String? _albumArtistName(dynamic album) {
  final artists = album.artists;
  if (artists is! List || artists.isEmpty) return null;
  final first = artists.first;
  return first is Map ? first['name']?.toString() : null;
}

/// [a] before [b] by the first of [keys] that tells them apart, ignoring
/// case; songs without a value go after those with one.
int _compareSongsBy(
    dynamic a, dynamic b, List<String? Function(dynamic)> keys) {
  for (final key in keys) {
    final x = (key(a) ?? '').trim().toLowerCase();
    final y = (key(b) ?? '').trim().toLowerCase();
    if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
    final c = x.compareTo(y);
    if (c != 0) return c;
  }
  return 0;
}

void sortAlbumNSingles(
  List albumList,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Date:
      compareFunction = (a, b) {
        if (a.year == null || b.year == null) {
          return 0.compareTo(0);
        }
        return a.year!.compareTo(b.year!);
      };
      break;
    case SortType.RecentlyPlayed:
      compareFunction = byLastPlayed<dynamic>(CollectionRecents.snapshot(),
          (a) => '${a.browseId}', (a) => '${a.title}');
      break;
    // Each artist's albums together, oldest first, as Spotify (Creator)
    // and Apple Music (Artist) list them; albums without one last.
    case SortType.Artist:
      compareFunction = (a, b) => _compareSongsBy(a, b, [
            _albumArtistName,
            (album) {
              final year = '${album.year ?? ''}'.trim();
              return year.isEmpty ? null : year.padLeft(4, '0');
            },
            (album) => album.title,
          ]);
    case SortType.Name:
    default:
      compareFunction =
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
      break;
  }

  albumList.sort(compareFunction);

  if (!isAscending) {
    List reversed = albumList.reversed.toList();
    albumList.clear();
    albumList.addAll(reversed);
  }
}

void sortPlayLists(
  List playlists,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;
  int titleSort(a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());

  switch (sortType) {
    case SortType.RecentlyPlayed:
      // When each was last played from (Playlist has no such field).
      compareFunction = byLastPlayed<dynamic>(CollectionRecents.snapshot(),
          (p) => '${p.playlistId}', (p) => '${p.title}');
      break;
    case SortType.Name:
    default:
      compareFunction = titleSort;
      break;
  }

  playlists.sort(compareFunction);

  if (!isAscending) {
    List reversed = playlists.reversed.toList();
    playlists.clear();
    playlists.addAll(reversed);
  }
}

void sortArtist(
  List artistList,
  SortType sortType,
  bool isAscending,
) {
  Comparator compareFunction;

  switch (sortType) {
    case SortType.Name:
    default:
      compareFunction =
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
      break;
  }

  artistList.sort(compareFunction);

  if (!isAscending) {
    List reversed = artistList.reversed.toList();
    artistList.clear();
    artistList.addAll(reversed);
  }
}

/// Return true if new version available
Future<bool> newVersionCheck(String currentVersion) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  try {
    final tags =
        (await dio.get("https://api.github.com/repos/Aimdi/Riff-mobile/tags"))
            .data;
    final availableVersion = tags[0]['name'] as String;
    return isNewerVersion(availableVersion, currentVersion);
  } catch (e) {
    return false;
  } finally {
    dio.close();
  }
}
