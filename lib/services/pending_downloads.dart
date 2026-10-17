import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';

/// The songs still to download, kept across restarts as Spotify and YouTube
/// Music keep theirs: the download queue lived in memory only, so Android
/// closing Riff in the background, a crash or the phone restarting in the
/// middle of a playlist's download dropped the rest of it, without a word.
///
/// One entry per song (its MediaItem, by id), so a song done is one delete,
/// and under [playlistsKey] each downloading playlist's or album's song ids
/// in order. The Downloader mirrors its queues here as they change
/// ([mirror]); at the next start, what's left is queued again ([load]).
class PendingDownloads {
  PendingDownloads._();

  static const boxName = 'PendingDownloads';
  static const playlistsKey = '#playlists';

  static Box? get _box => Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// Nothing left to download (or the box isn't open).
  static bool get isEmpty => _box?.isEmpty ?? true;

  /// Makes the box hold [songs] (the queue) and [playlists] (each one's
  /// songs, by its id), and nothing else.
  static Future<void> mirror(
      List<MediaItem> songs, Map<String, List<MediaItem>> playlists) async {
    final box = _box;
    if (box == null) return;
    final wanted = <String, MediaItem>{
      for (final s in songs) s.id: s,
      for (final list in playlists.values)
        for (final s in list) s.id: s,
    };
    final stale = [
      for (final k in box.keys)
        if (k != playlistsKey && !wanted.containsKey(k)) k
    ];
    if (stale.isNotEmpty) await box.deleteAll(stale);
    final missing = {
      for (final e in wanted.entries)
        if (!box.containsKey(e.key)) e.key: MediaItemBuilder.toJson(e.value)
    };
    if (missing.isNotEmpty) await box.putAll(missing);
    final lists = {
      for (final e in playlists.entries) e.key: [for (final s in e.value) s.id]
    };
    if (lists.isEmpty) {
      if (box.containsKey(playlistsKey)) await box.delete(playlistsKey);
    } else {
      await box.put(playlistsKey, lists);
    }
  }

  /// What was left: the songs on their own, and each playlist's songs (by
  /// its id), not yet downloaded ([isDownloaded]).
  static ({List<MediaItem> songs, Map<String, List<MediaItem>> playlists}) load(
      {required bool Function(String id) isDownloaded}) {
    final box = _box;
    if (box == null || box.isEmpty) {
      return (songs: const [], playlists: const {});
    }
    final byId = <String, MediaItem>{};
    for (final k in box.keys) {
      if (k == playlistsKey) continue;
      try {
        byId['$k'] = MediaItemBuilder.fromJson(box.get(k));
      } catch (_) {
        // A damaged entry: that one is lost, not the rest.
      }
    }
    final playlists = <String, List<MediaItem>>{};
    final inPlaylists = <String>{};
    final raw = box.get(playlistsKey);
    if (raw is Map) {
      for (final e in raw.entries) {
        final ids = e.value is List ? (e.value as List) : const [];
        final songs = [
          for (final id in ids)
            if (byId['$id'] != null) byId['$id']!
        ];
        inPlaylists.addAll(songs.map((s) => s.id));
        // A playlist whose songs are all there is done.
        if (songs.any((s) => !isDownloaded(s.id))) {
          playlists['${e.key}'] = songs;
        }
      }
    }
    final songs = [
      for (final s in byId.values)
        if (!inPlaylists.contains(s.id) && !isDownloaded(s.id)) s
    ];
    return (songs: songs, playlists: playlists);
  }
}
