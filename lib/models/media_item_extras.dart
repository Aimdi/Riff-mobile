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

  /// Marked explicit by YouTube Music (the "E" badge).
  bool get isExplicit => extrasBool('isExplicit');

  /// The album the song is on, told apart from others of the same name: its
  /// id (YouTube Music's, your music server's), the phone's album (Media
  /// Store), else its name. Null when it's on none.
  String? get albumKey {
    final album = extras?['album'];
    if (album is Map) {
      final id = album['id'];
      if (id is String && id.isNotEmpty) return 'id:$id';
    }
    final onPhone = extrasString('albumId');
    if (onPhone != null) return 'device:$onPhone';
    final name = album is Map && album['name'] is String
        ? album['name'] as String
        : this.album;
    final key = name?.trim().toLowerCase() ?? '';
    return key.isEmpty ? null : 'name:$key';
  }

  /// The song's number on its album ("3" of YouTube Music's "3/12"; the
  /// phone's counts the disc in thousands, 2003 for disc 2's third). Null
  /// when unknown.
  int? get albumTrackNumber {
    final details = extrasString('trackDetails');
    if (details == null) return null;
    final number = int.tryParse(details.split('/').first.trim());
    return number != null && number > 0 ? number : null;
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

  /// A free LibriVox chapter (`lv_` ids from FreeAudiobookService).
  bool get isFreeAudiobook => id.startsWith('lv_');

  /// Any audiobook chapter, from a server or the free catalog.
  bool get isAudiobook => isAudiobookshelf || isFreeAudiobook;

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
