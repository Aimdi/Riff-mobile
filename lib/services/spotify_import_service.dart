import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../models/media_Item_builder.dart';
import '../utils/helper.dart';
import 'deezer_metadata_service.dart';
import 'music_service.dart';
import 'spotify_match_store.dart';
import 'spotify_match.dart';

/// One track as listed on a public Spotify playlist / album page.
class SpotifyTrackRef {
  const SpotifyTrackRef({
    required this.id,
    required this.title,
    required this.artists,
    this.durationMs,
    this.isrc,
    this.album,
    this.artUrl,
  });

  final String id;
  final String title;
  final String artists;
  final int? durationMs;

  /// Album name and cover, when the source has them (Web API).
  final String? album;
  final String? artUrl;

  /// International Standard Recording Code, when the source has one (CSV
  /// exports): searched first, as it names the exact recording.
  final String? isrc;

  String get searchQuery {
    // Spotify subtitles use non-breaking spaces between artists.
    final cleanedArtists = artists
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$title $cleanedArtists'.trim();
  }
}

class SpotifyPlaylistImport {
  const SpotifyPlaylistImport({
    required this.id,
    required this.name,
    required this.type,
    required this.tracks,
    this.coverUrl,
  });

  final String id;
  final String name;
  final String type; // playlist | album
  final List<SpotifyTrackRef> tracks;
  final String? coverUrl;
}

/// Spotube-style public Spotify metadata import.
///
/// Does **not** require a Spotify login. Public playlists / albums are loaded
/// via Spotify's embed page (`open.spotify.com/embed/...`), then each track is
/// resolved on YouTube Music by title + artist search — the same idea Spotube
/// uses when bridging Spotify libraries to free sources.
class SpotifyImportService extends GetxService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'user-agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'accept-language': 'en-US,en;q=0.9',
    },
    responseType: ResponseType.plain,
  ));

  /// Metadata-only enrichment used to recover durations the Spotify embed
  /// omits. Optional so tests and offline use can disable it outright.
  DeezerMetadataService? _deezer = DeezerMetadataService();

  /// Disable (or inject) the Deezer enrichment step.
  set deezer(DeezerMetadataService? service) => _deezer = service;

  /// Parse playlist / album id from a Spotify share URL or URI.
  /// Returns `(type, id)` e.g. `('playlist', '37i9d...')`.
  static (String, String)? parseSpotifyUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // spotify:playlist:ID / spotify:album:ID
    final uriMatch =
        RegExp(r'spotify:(playlist|album):([A-Za-z0-9]+)').firstMatch(raw);
    if (uriMatch != null) {
      return (uriMatch.group(1)!, uriMatch.group(2)!);
    }

    // https://open.spotify.com/playlist/ID?...  (also international.spotify.com)
    final urlMatch = RegExp(
      r'(?:open|play)\.spotify\.com/(?:intl-[a-z]{2}/)?(playlist|album)/([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (urlMatch != null) {
      return (urlMatch.group(1)!.toLowerCase(), urlMatch.group(2)!);
    }

    // Bare id — assume playlist
    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(raw)) {
      return ('playlist', raw);
    }
    return null;
  }

  /// Fetch public playlist / album metadata + track list from Spotify embed.
  Future<SpotifyPlaylistImport> fetchPublicCollection(String urlOrId) async {
    final parsed = parseSpotifyUrl(urlOrId);
    if (parsed == null) {
      throw ArgumentError('Invalid Spotify playlist/album URL');
    }
    final (type, id) = parsed;
    final embedUrl = 'https://open.spotify.com/embed/$type/$id';

    final res = await _dio.get(embedUrl);
    final html = res.data.toString();

    final nextData = _extractNextData(html);
    if (nextData == null) {
      throw StateError('Could not read Spotify embed data');
    }

    final entity =
        nextData['props']?['pageProps']?['state']?['data']?['entity'] as Map?;
    if (entity == null) {
      throw StateError('Spotify collection not found or private');
    }

    final name =
        (entity['name'] ?? entity['title'] ?? 'Spotify import').toString();
    String? coverUrl;
    final sources = entity['coverArt']?['sources'];
    if (sources is List && sources.isNotEmpty) {
      coverUrl =
          sources.last['url']?.toString() ?? sources.first['url']?.toString();
    }

    final trackList = entity['trackList'] as List? ?? const [];
    final tracks = <SpotifyTrackRef>[];
    for (final t in trackList) {
      if (t is! Map) continue;
      final uri = (t['uri'] ?? '').toString();
      final trackId = uri.contains(':') ? uri.split(':').last : uri;
      final title = (t['title'] ?? '').toString();
      if (title.isEmpty) continue;
      tracks.add(SpotifyTrackRef(
        id: trackId,
        title: title,
        artists: (t['subtitle'] ?? '').toString(),
        durationMs:
            t['duration'] is num ? (t['duration'] as num).toInt() : null,
      ));
    }

    if (tracks.isEmpty) {
      throw StateError(
          'No tracks found — playlist may be private or region-locked');
    }

    printINFO('Spotify import: "$name" ($type) → ${tracks.length} tracks');
    return SpotifyPlaylistImport(
      id: id,
      name: name,
      type: type,
      tracks: tracks,
      coverUrl: coverUrl,
    );
  }

  Map<String, dynamic>? _extractNextData(String html) {
    const marker = 'id="__NEXT_DATA__"';
    final i = html.indexOf(marker);
    if (i < 0) return null;
    final start = html.indexOf('>', i);
    if (start < 0) return null;
    final end = html.indexOf('</script>', start);
    if (end < 0) return null;
    final jsonStr = html.substring(start + 1, end).trim();
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Resolve Spotify tracks to YouTube Music [MediaItem]s via song search.
  ///
  /// [onProgress] is called with `(done, total)` after each track.
  Future<List<MediaItem>> resolveTracksToYtm(
    List<SpotifyTrackRef> tracks, {
    void Function(int done, int total)? onProgress,
    int concurrency = 3,
  }) async =>
      (await resolveTracksDetailed(tracks,
              onProgress: onProgress, concurrency: concurrency))
          .whereType<MediaItem>()
          .toList();

  /// Like [resolveTracksToYtm], but one entry per track (null when nothing
  /// matched), for a matched / unmatched summary.
  ///
  /// Each Spotify track is looked up in [SpotifyMatchStore] first (a match
  /// found before, or one the listener picked), and new matches are stored.
  Future<List<MediaItem?>> resolveTracksDetailed(
    List<SpotifyTrackRef> tracks, {
    void Function(int done, int total)? onProgress,
    int concurrency = 3,
  }) async {
    await SpotifyMatchStore.open();
    final results = List<MediaItem?>.filled(tracks.length, null);
    var done = 0;

    Future<void> resolveOne(int index) async {
      final t = tracks[index];
      try {
        results[index] = await resolveTrack(t);
      } catch (e) {
        printERROR('YTM resolve failed for "${t.searchQuery}": $e');
      } finally {
        done++;
        onProgress?.call(done, tracks.length);
      }
    }

    // Simple worker pool
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= tracks.length) return;
        await resolveOne(i);
      }
    }

    final n = concurrency.clamp(1, 6);
    await Future.wait(List.generate(n, (_) => worker()));

    return results;
  }

  /// One track's YouTube Music match: stored match first, then search
  /// (ISRC, then title and artist). Null when nothing is close enough.
  Future<MediaItem?> resolveTrack(SpotifyTrackRef t) async {
    // Playback calls this directly, often before anything opened the
    // store; reading it closed missed the stored match (even one the
    // listener picked) and searched again.
    await SpotifyMatchStore.open();
    final cached = SpotifyMatchStore.itemFor(t.id);
    if (cached != null) return cached;
    final ranked = await rankCandidates(t, stopAtConfident: true);
    final best = ranked.isEmpty ? null : ranked.first;
    if (best == null || best.score < kMinAcceptableMatch) {
      printINFO(
          'Spotify import: no confident match for "${t.searchQuery}", skipped');
      return null;
    }
    await SpotifyMatchStore.putAuto(t.id, best.item, best.score);
    return best.item;
  }

  /// YouTube Music candidates for [t], best first, each with its score:
  /// the ISRC search (it names the exact recording), then the title and
  /// artist search, or [query] instead of both. With [stopAtConfident], the
  /// second search is skipped when the ISRC already gave an acceptable
  /// match.
  Future<List<ScoredCandidate<MediaItem>>> rankCandidates(SpotifyTrackRef t,
      {String? query, bool stopAtConfident = false}) async {
    final music = Get.find<MusicServices>();
    // The Spotify embed page often omits duration, and duration is the
    // strongest signal for separating a studio take from a remix, live cut
    // or sped-up upload. Deezer's public API needs no auth and returns the
    // canonical length, so fill the gap before scoring. Metadata only — no
    // audio is fetched from Deezer. Skipped entirely when Spotify already
    // gave us a duration, so the common path costs nothing.
    var spotifyDurationMs = t.durationMs;
    if (spotifyDurationMs == null && _deezer != null) {
      final meta = await _deezer!.lookup(t.title, t.artists);
      spotifyDurationMs = meta?.durationMs;
    }

    Future<List<MediaItem>> candidatesFor(String q) async {
      final res = await music.search(q, filter: 'songs', limit: 5);
      // Collect every candidate rather than taking the first hit: YouTube
      // routinely ranks a remix, live cut, sped-up upload or karaoke
      // version above the actual recording.
      final out = <MediaItem>[];
      for (final entry in res.entries) {
        if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
        final list = entry.value;
        if (list is! List) continue;
        for (final item in list) {
          if (item is MediaItem) {
            out.add(item);
          } else if (item is Map && item['videoId'] != null) {
            out.add(MediaItemBuilder.fromJson(item));
          }
        }
      }
      return out;
    }

    double score(MediaItem c) => matchScore(
          spotifyTitle: t.title,
          spotifyArtists: t.artists,
          spotifyDurationMs: spotifyDurationMs,
          candidateTitle: c.title,
          candidateArtist: c.artist,
          candidateDuration: c.duration,
        );

    final seen = <String>{};
    final ranked = <ScoredCandidate<MediaItem>>[];
    void addAll(List<MediaItem> items) {
      for (final c in items) {
        if (seen.add(c.id)) ranked.add(ScoredCandidate(c, score(c)));
      }
    }

    if (query != null) {
      addAll(await candidatesFor(query));
    } else {
      if (t.isrc != null) addAll(await candidatesFor(t.isrc!));
      final confident = ranked.any((c) => c.score >= kMinAcceptableMatch);
      if (!(stopAtConfident && confident)) {
        addAll(await candidatesFor(t.searchQuery));
      }
    }
    return sortCandidates(ranked);
  }
}
