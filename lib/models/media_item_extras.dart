import 'package:audio_service/audio_service.dart';

/// Typed reads of [MediaItem.extras]. Hive / YTM maps are untyped;
/// these helpers keep nulls and wrong shapes from throwing.
extension MediaItemExtras on MediaItem {
  String? extrasString(String key) {
    final v = extras?[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  bool extrasBool(String key, {bool fallback = false}) {
    final v = extras?[key];
    if (v is bool) return v;
    if (v == true || v == 1 || v == 'true') return true;
    if (v == false || v == 0 || v == 'false') return false;
    return fallback;
  }

  double extrasDouble(String key, {double fallback = 0}) {
    final v = extras?[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int extrasInt(String key, {int fallback = 0}) {
    final v = extras?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Stream / file URL stored by [MediaItemBuilder] and cache writes.
  String? get extrasUrl => extrasString('url');

  String? get discoverySourceWire => extrasString('discoverySource');

  String? get streamSource => extrasString('streamSource');

  String? get chaptersUrl => extrasString('chaptersUrl');

  String? get absSessionId => extrasString('absSessionId');

  double get absStartOffsetSec => extrasDouble('absStartOffsetSec');

  bool get isPodcastEpisode =>
      extrasBool('isPodcast') || id.startsWith('podcast_');

  bool get isAudiobookshelf =>
      id.startsWith('abs_') || streamSource == 'audiobookshelf';

  List<Map<String, dynamic>> get extrasArtists {
    final raw = extras?['artists'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

/// Distinct media ids, skipping blanks.
Set<String> mediaItemIds(Iterable<MediaItem> items) {
  final ids = <String>{};
  for (final item in items) {
    if (item.id.isNotEmpty) ids.add(item.id);
  }
  return ids;
}
