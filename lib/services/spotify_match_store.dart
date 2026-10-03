import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';

/// Which YouTube Music recording a Spotify track plays as.
class SpotifyMatchEntry {
  const SpotifyMatchEntry({
    required this.item,
    this.score = 0,
    this.manual = false,
    this.at = 0,
  });

  /// The stored MediaItem JSON (`MediaItemBuilder.toJson`).
  final Map<String, dynamic> item;
  final double score;

  /// Picked by the listener with "Change match…": never replaced
  /// automatically.
  final bool manual;
  final int at;

  String get videoId => '${item['videoId'] ?? ''}';

  Map<String, dynamic> toJson() =>
      {'item': item, 'score': score, 'manual': manual, 'at': at};

  static SpotifyMatchEntry? fromJson(Object? j) {
    if (j is! Map || j['item'] is! Map) return null;
    final item = Map<String, dynamic>.from(j['item'] as Map);
    if ('${item['videoId'] ?? ''}'.isEmpty) return null;
    final score = j['score'];
    final at = j['at'];
    return SpotifyMatchEntry(
      item: item,
      score: score is num ? score.toDouble() : 0,
      manual: j['manual'] == true,
      at: at is int ? at : 0,
    );
  }
}

/// Whether a match for this Spotify id is worth keeping: real Spotify ids
/// only (CSV rows have made-up ones).
bool cacheableSpotifyId(String id) =>
    id.isNotEmpty && !id.startsWith('csv_') && !id.contains(' ');

/// Whether an automatic match may be stored over [existing]: never over a
/// listener's own choice.
bool mayStoreAutoMatch(SpotifyMatchEntry? existing) =>
    existing == null || !existing.manual;

/// Spotify track id → its YouTube Music match, in box `SpotifyMatches`, so
/// each track is searched for once and a corrected match sticks.
class SpotifyMatchStore {
  SpotifyMatchStore._();

  static const box = 'SpotifyMatches';

  static Future<Box?> open() async {
    try {
      return Hive.isBoxOpen(box) ? Hive.box(box) : await Hive.openBox(box);
    } catch (_) {
      return null;
    }
  }

  static Box? get _box => Hive.isBoxOpen(box) ? Hive.box(box) : null;

  static SpotifyMatchEntry? get(String spotifyId) =>
      cacheableSpotifyId(spotifyId)
          ? SpotifyMatchEntry.fromJson(_box?.get(spotifyId))
          : null;

  static MediaItem? itemFor(String spotifyId) {
    final e = get(spotifyId);
    if (e == null) return null;
    try {
      return MediaItemBuilder.fromJson(e.item);
    } catch (_) {
      return null;
    }
  }

  /// Store an automatic match (unless the listener picked one).
  static Future<void> putAuto(String spotifyId, MediaItem item, double score,
      {DateTime? now}) async {
    if (!cacheableSpotifyId(spotifyId)) return;
    final b = await open();
    if (b == null || !mayStoreAutoMatch(get(spotifyId))) return;
    await b.put(
        spotifyId,
        SpotifyMatchEntry(
          item: MediaItemBuilder.toJson(item),
          score: score,
          at: (now ?? DateTime.now()).millisecondsSinceEpoch,
        ).toJson());
  }

  /// The listener's own choice: kept for good.
  static Future<void> putManual(String spotifyId, MediaItem item,
      {DateTime? now}) async {
    if (!cacheableSpotifyId(spotifyId)) return;
    final b = await open();
    await b?.put(
        spotifyId,
        SpotifyMatchEntry(
          item: MediaItemBuilder.toJson(item),
          score: 1,
          manual: true,
          at: (now ?? DateTime.now()).millisecondsSinceEpoch,
        ).toJson());
  }

  /// Forget the match (it's searched for again next time).
  static Future<void> remove(String spotifyId) async =>
      (await open())?.delete(spotifyId);
}
