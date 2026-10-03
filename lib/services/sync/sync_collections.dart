/// The synced collections: where each one lives in the app (Hive boxes) and
/// on the server, how to read it as records and how to take in the result
/// of a merge. The format and rules are in docs/sync-format.md.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/podcast_bookmarks.dart';
import '/services/podcast_segments.dart';
import '/services/podcast_service.dart';
import '/ui/screens/Library/library_controller.dart';
import '/utils/hive_boxes.dart';
import 'sync_merge.dart';
import 'sync_opml.dart';
import 'sync_records.dart';

/// A file's records plus the top-level fields this app doesn't know.
typedef DecodedFile = ({
  Map<String, SyncRecord> records,
  Map<String, dynamic> extra
});

abstract class SyncCollection {
  const SyncCollection();

  /// Collection name in the format (`podcast.episodes`).
  String get name;

  /// Path under `Riff/`.
  String get path;

  String get contentType => 'application/json; charset=utf-8';

  /// What the app holds now, by record id.
  Future<Map<String, LocalItem>> readLocal();

  /// Take in [changes]: the winning version for each id that differs.
  Future<void> apply(Map<String, SyncRecord> changes);

  DecodedFile decode(String text) {
    final f = SyncFile.decode(text, collection: name);
    if (!syncVersionSupported(f.version)) {
      throw const FormatException('Newer format');
    }
    return (records: f.records, extra: f.extra);
  }

  String encode(Map<String, SyncRecord> records,
          {required Map<String, dynamic> extra,
          required int nowMs,
          required String device}) =>
      SyncFile(collection: name, records: records, extra: extra).encode();

  /// Fix up what was read before merging (see [PodcastEpisodesSync]).
  /// Null when nothing changed.
  Map<String, SyncRecord>? adopt(
          Map<String, SyncRecord> remote, String device) =>
      null;
}

Box? _box(String name) => Hive.isBoxOpen(name) ? Hive.box(name) : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

// ── Subscriptions ─────────────────────────────────────────────────────

class PodcastSubscriptionsSync extends SyncCollection {
  const PodcastSubscriptionsSync();

  @override
  String get name => 'podcast.subscriptions';
  @override
  String get path => 'podcasts/subscriptions.opml';
  @override
  String get contentType => 'text/x-opml; charset=utf-8';

  @override
  DecodedFile decode(String text) =>
      (records: decodeSubscriptionsOpml(text), extra: const {});

  @override
  String encode(Map<String, SyncRecord> records,
          {required Map<String, dynamic> extra,
          required int nowMs,
          required String device}) =>
      encodeSubscriptionsOpml(records, nowMs: nowMs, device: device);

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final box = _box('PodcastSubs');
    if (box == null) return {};
    final out = <String, LocalItem>{};
    for (final key in box.keys) {
      final v = _map(box.get(key));
      final feed = '${v['feedUrl'] ?? key}';
      if (feed.isEmpty) continue;
      final at = v['subscribedAt'];
      out[feed] = LocalItem(
        compactData({
          'feedUrl': feed,
          'title': v['title']?.toString() ?? '',
          'author': v['author']?.toString(),
          'artwork': v['artwork']?.toString(),
        }),
        editedAt: at is int && at > 0 ? at : null,
      );
    }
    return out;
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    final box = _box('PodcastSubs');
    if (box == null) return;
    for (final e in changes.entries) {
      if (e.value.deleted) {
        await box.delete(e.key);
        continue;
      }
      final d = e.value.data ?? const {};
      await box.put(e.key, {
        ..._map(box.get(e.key)),
        'title': d['title'],
        'author': d['author'],
        'artwork': d['artwork'],
        'feedUrl': e.key,
        'subscribedAt': e.value.updatedAt,
      });
    }
    if (changes.isNotEmpty) PodcastService.subsRev.value++;
  }
}

// ── Episode progress and played state ─────────────────────────────────

class PodcastEpisodesSync extends SyncCollection {
  const PodcastEpisodesSync();

  @override
  String get name => 'podcast.episodes';
  @override
  String get path => 'podcasts/episodes.json';

  @override
  Map<String, SyncRecord>? adopt(
          Map<String, SyncRecord> remote, String device) =>
      adoptForeignEpisodeIds(remote, device);

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final out = <String, LocalItem>{};
    final played = _box('PodcastPlayed');
    if (played != null) {
      for (final key in played.keys) {
        final at = played.get(key);
        out['$key'] = LocalItem(episodeDataPlayed('$key'),
            editedAt: at is int && at > 0 ? at : null);
      }
    }
    final progress = _box('PodcastProgress');
    if (progress != null) {
      for (final key in progress.keys) {
        final row = progress.get(key);
        if (row is! Map) continue;
        final at = row['updatedAt'];
        // Played wins if both are somehow there (the app drops one).
        out.putIfAbsent(
            '$key',
            () => LocalItem(episodeDataFromProgress('$key', row),
                editedAt: at is int && at > 0 ? at : null));
      }
    }
    return out;
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    final progress = _box('PodcastProgress');
    final played = _box('PodcastPlayed');
    if (progress == null || played == null) return;
    for (final e in changes.entries) {
      if (e.key.startsWith('url:')) continue; // adopted under our id
      final r = e.value;
      if (r.deleted) {
        await progress.delete(e.key);
        await played.delete(e.key);
      } else if (r.data?['played'] == true) {
        await progress.delete(e.key);
        await played.put(e.key, r.updatedAt);
      } else {
        await played.delete(e.key);
        await progress.put(
            e.key,
            progressRowFromEpisode(
                e.key, r.data ?? const {}, r.updatedAt, progress.get(e.key)));
      }
    }
  }
}

// ── Bookmarks ─────────────────────────────────────────────────────────

class PodcastBookmarksSync extends SyncCollection {
  const PodcastBookmarksSync();

  @override
  String get name => 'podcast.bookmarks';
  @override
  String get path => 'podcasts/bookmarks.json';

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final box = _box(PodcastBookmarkStore.box);
    if (box == null) return {};
    final out = <String, LocalItem>{};
    for (final v in box.values) {
      final bm = PodcastBookmark.fromJson(v);
      if (bm == null) continue;
      out[bm.id] = LocalItem(bookmarkData(bm.toJson()),
          editedAt: bm.updatedAt ?? (bm.createdAt > 0 ? bm.createdAt : null));
    }
    return out;
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    final box = _box(PodcastBookmarkStore.box);
    if (box == null) return;
    for (final e in changes.entries) {
      if (e.value.deleted) {
        await box.delete(e.key);
        continue;
      }
      final d = Map<String, dynamic>.from(e.value.data ?? const {});
      final ep = localEpisodeId('${d['episodeId'] ?? ''}', data: d);
      if (ep == null) continue;
      final bm = PodcastBookmark.fromJson(
          {...d, 'id': e.key, 'episodeId': ep, 'updatedAt': e.value.updatedAt});
      if (bm == null) continue;
      await box.put(bm.id, bm.toJson());
    }
    if (changes.isNotEmpty) PodcastBookmarkStore.rev.value++;
  }
}

// ── Manual segment marks ──────────────────────────────────────────────

class PodcastSegmentsSync extends SyncCollection {
  const PodcastSegmentsSync();

  @override
  String get name => 'podcast.segments';
  @override
  String get path => 'podcasts/segments.json';

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final box = _box(PodcastSegmentStore.manualBox);
    if (box == null) return {};
    final out = <String, LocalItem>{};
    for (final key in box.keys) {
      for (final s in PodcastSegmentStore.manual('$key')) {
        out[segmentRecordId('$key', s.id)] = LocalItem({
          'episodeId': '$key',
          'segmentId': s.id,
          'start': s.start,
          'end': s.end,
          'category': s.category.apiName,
        }, editedAt: segmentCreatedAt(s.id));
      }
    }
    return out;
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    final box = _box(PodcastSegmentStore.manualBox);
    if (box == null) return;
    // Group by episode: one write per episode.
    final byEpisode = <String, Map<String, SyncRecord>>{};
    for (final e in changes.entries) {
      final parsed = parseSegmentRecordId(e.key);
      if (parsed == null) continue;
      final ep = localEpisodeId(parsed.episodeId, data: e.value.data);
      if (ep == null) continue;
      (byEpisode[ep] ??= {})[parsed.segmentId] = e.value;
    }
    for (final entry in byEpisode.entries) {
      final list = {
        for (final s in PodcastSegmentStore.manual(entry.key)) s.id: s.toJson()
      };
      entry.value.forEach((segId, r) {
        if (r.deleted) {
          list.remove(segId);
          return;
        }
        final seg = PodcastSegment.fromJson({
          ...?r.data,
          'id': segId,
          'source': SegmentSource.manual.name,
        });
        if (seg != null) list[segId] = seg.toJson();
      });
      if (list.isEmpty) {
        await box.delete(entry.key);
      } else {
        final sorted = list.values.toList()
          ..sort((a, b) => (a['start'] as num).compareTo(b['start'] as num));
        await box.put(entry.key, sorted);
      }
    }
    if (byEpisode.isNotEmpty) PodcastSegmentStore.rev.value++;
  }
}

// ── Playlists ─────────────────────────────────────────────────────────

class PlaylistsSync extends SyncCollection {
  const PlaylistsSync();

  @override
  String get name => 'library.playlists';
  @override
  String get path => 'library/playlists.json';

  static List<Map> _songs(Box box) => [
        for (final v in box.values)
          if (v is Map && v['videoId'] != null) v
      ];

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final out = <String, LocalItem>{};
    final lib = await HiveBoxes.open('LibraryPlaylists');
    for (final v in lib.values) {
      if (v is! Map) continue;
      final id = '${v['playlistId'] ?? ''}';
      final kind = playlistKind(v);
      if (id.isEmpty || kind == null) continue;
      final songs =
          kind == 'local' ? _songs(await HiveBoxes.open(id)) : const <Map>[];
      out[id] = LocalItem(playlistData(v, kind, songs));
    }
    return out;
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    if (changes.isEmpty) return;
    final lib = await HiveBoxes.open('LibraryPlaylists');
    for (final e in changes.entries) {
      final id = e.key;
      final r = e.value;
      // Favourites sync song by song (FavoritesSync).
      if (id == favoritesPlaylistId) continue;
      if (r.deleted) {
        await lib.delete(id);
        if (await Hive.boxExists(id)) {
          final songs = await HiveBoxes.open(id);
          await songs.deleteFromDisk();
        }
        continue;
      }
      final d = r.data ?? const {};
      await lib.put(id, playlistEntryFromSync(id, d));
      if (d['kind'] == 'local') {
        final box = await HiveBoxes.open(id);
        final songs = [
          for (final s in (d['songs'] as List? ?? const []))
            if (s is Map && s['videoId'] != null) storedSongFromSync(s)
        ];
        await box.clear();
        await box.putAll({for (var i = 0; i < songs.length; i++) i: songs[i]});
      }
    }
    if (Get.isRegistered<LibraryPlaylistsController>()) {
      Get.find<LibraryPlaylistsController>().refreshLib();
    }
  }
}

/// Favourites, one record per song: every device has this list, so it
/// merges song by song instead of one device's list replacing another's.
class FavoritesSync extends SyncCollection {
  const FavoritesSync();

  @override
  String get name => 'library.favorites';
  @override
  String get path => 'library/favorites.json';

  @override
  Future<Map<String, LocalItem>> readLocal() async {
    final fav = await HiveBoxes.fav();
    return {
      for (final v in fav.values)
        if (v is Map && v['videoId'] != null)
          '${v['videoId']}': LocalItem(syncSongFromStored(v))
    };
  }

  @override
  Future<void> apply(Map<String, SyncRecord> changes) async {
    if (changes.isEmpty) return;
    final fav = await HiveBoxes.fav();
    for (final e in changes.entries) {
      if (e.value.deleted) {
        await fav.delete(e.key);
      } else {
        await fav.put(e.key, {
          ...storedSongFromSync(e.value.data ?? const {}),
          'videoId': e.key
        });
      }
    }
    if (Get.isRegistered<LibraryPlaylistsController>()) {
      Get.find<LibraryPlaylistsController>().refreshLib();
    }
  }
}

/// Everything that syncs, podcasts first.
const syncCollections = <SyncCollection>[
  PodcastSubscriptionsSync(),
  PodcastEpisodesSync(),
  PodcastBookmarksSync(),
  PodcastSegmentsSync(),
  PlaylistsSync(),
  FavoritesSync(),
];
