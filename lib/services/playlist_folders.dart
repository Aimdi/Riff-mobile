/// Folders for the Library's playlists, as Spotify's Your Library has
/// them: a folder holds playlists, which then show inside it instead of
/// among the rest; Riff's own four and the pinned ones stay at the top.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/playlist.dart';

class PlaylistFolder {
  const PlaylistFolder(
      {required this.id, required this.name, this.playlists = const []});

  final String id;
  final String name;

  /// Its playlists' ids, in the order they went in.
  final List<String> playlists;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'playlists': playlists};

  static PlaylistFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    final name = '${raw['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) return null;
    final playlists = raw['playlists'];
    return PlaylistFolder(
        id: id,
        name: name,
        playlists:
            playlists is List ? playlists.map((p) => '$p').toList() : const []);
  }

  PlaylistFolder copyWith({String? name, List<String>? playlists}) =>
      PlaylistFolder(
          id: id,
          name: name ?? this.name,
          playlists: playlists ?? this.playlists);
}

class PlaylistFolders {
  PlaylistFolders._();

  /// AppPrefs: the folders, in the order they were made.
  static const key = 'playlistFolders';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static List<PlaylistFolder> get folders {
    final raw = _prefs?.get(key);
    return raw is List
        ? raw.map(PlaylistFolder.fromJson).whereType<PlaylistFolder>().toList()
        : <PlaylistFolder>[];
  }

  static PlaylistFolder? byId(String id) =>
      folders.firstWhereOrNull((f) => f.id == id);

  /// The folder [playlistId] is in, if any.
  static PlaylistFolder? folderOf(String playlistId) =>
      folders.firstWhereOrNull((f) => f.playlists.contains(playlistId));

  /// A new folder named [name] (last), with [playlistId] moved into it.
  static Future<PlaylistFolder> create(String name,
      {String? playlistId}) async {
    final folder = PlaylistFolder(
        id: 'folder_${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim());
    await _save([
      for (final f in folders) playlistId == null ? f : _without(f, playlistId),
      folder.copyWith(playlists: [if (playlistId != null) playlistId]),
    ]);
    return byId(folder.id) ?? folder;
  }

  static Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _save(
        [for (final f in folders) f.id == id ? f.copyWith(name: trimmed) : f]);
  }

  /// Takes the folder away, its playlists back among the rest; what it
  /// was and where, for [restore] (Undo). Null when there's no such folder.
  static Future<(PlaylistFolder, int)?> delete(String id) async {
    final all = folders;
    final index = all.indexWhere((f) => f.id == id);
    if (index < 0) return null;
    final folder = all.removeAt(index);
    await _save(all);
    return (folder, index);
  }

  /// Puts a [delete]d folder back where it was, with the playlists it had
  /// that aren't in another folder since.
  static Future<void> restore(PlaylistFolder folder, int index) async {
    final all = folders.where((f) => f.id != folder.id).toList();
    final filed = {for (final f in all) ...f.playlists};
    all.insert(
        index.clamp(0, all.length),
        folder.copyWith(
            playlists:
                folder.playlists.where((p) => !filed.contains(p)).toList()));
    await _save(all);
  }

  /// Moves [playlistId] into the folder [folderId] (last), or out of any
  /// folder when it's null.
  static Future<void> move(String playlistId, String? folderId) async {
    await _save([
      for (final f in folders)
        f.id == folderId
            ? f.copyWith(playlists: [
                ...f.playlists.where((p) => p != playlistId),
                playlistId,
              ])
            : _without(f, playlistId),
    ]);
  }

  /// [playlistId] left the Library: out of its folder.
  static Future<void> forget(String playlistId) async {
    if (folderOf(playlistId) == null) return;
    await move(playlistId, null);
  }

  static PlaylistFolder _without(PlaylistFolder f, String playlistId) =>
      f.playlists.contains(playlistId)
          ? f.copyWith(
              playlists: f.playlists.where((p) => p != playlistId).toList())
          : f;

  static Future<void> _save(List<PlaylistFolder> next) async {
    await _prefs?.put(key, [for (final f in next) f.toJson()]);
    rev.value++;
  }
}

/// What Library › Playlists shows, in order: [playlists] as ordered
/// (Riff's own four, the pinned ones, then the rest), with the [folders]
/// after the [leading] ones (own and pinned, which stay out here even
/// when filed) and the playlists filed in a folder only in it. While
/// [searching], every match shows and the folders don't.
List<Object> libraryPlaylistItems(
    List<Playlist> playlists, List<PlaylistFolder> folders,
    {required bool Function(String id) leading, bool searching = false}) {
  if (searching || folders.isEmpty) return playlists;
  final filed = {for (final f in folders) ...f.playlists};
  final head = [
    for (final p in playlists)
      if (leading(p.playlistId)) p
  ];
  return [
    ...head,
    ...folders,
    for (final p in playlists)
      if (!leading(p.playlistId) && !filed.contains(p.playlistId)) p
  ];
}

/// [folder]'s playlists that are in the Library ([playlists]), in the
/// folder's order.
List<Playlist> folderPlaylists(
    PlaylistFolder folder, List<Playlist> playlists) {
  final byId = {for (final p in playlists) p.playlistId: p};
  return [
    for (final id in folder.playlists)
      if (byId[id] != null) byId[id]!
  ];
}
