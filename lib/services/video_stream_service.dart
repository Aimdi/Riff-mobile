import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/services/stream_service.dart';
import '/utils/helper.dart';

/// In-player video quality tier: High = full quality up to 1080p,
/// Low = data/battery saver up to 480p. Both prefer **video-only**
/// streams — video mode pairs them with the music pipeline's own audio
/// stream inside one mpv engine, so no muxed audio is ever decoded.
enum VideoQuality {
  low,
  high,
}

/// One resolvable video stream for the in-player video mode.
class VideoStreamInfo {
  const VideoStreamInfo({
    required this.url,
    required this.width,
    required this.height,
    this.itag,
    this.mimeType,
    this.hasAudio = true,
  });

  final String url;
  final int width;
  final int height;
  final int? itag;
  final String? mimeType;

  /// True for progressive/muxed; false for adaptive video-only.
  final bool hasAudio;

  double get aspectRatio =>
      width > 0 && height > 0 ? width / height : 16 / 9;
}

class _CachedStream {
  _CachedStream(this.info, this.fetchedAt);
  final VideoStreamInfo info;
  final DateTime fetchedAt;
}

class VideoStreamService {
  VideoStreamService._();

  static const _newPipeChannel = MethodChannel('riff/newpipe');
  /// Insertion-ordered, so the first key is the least recently used.
  static final Map<String, _CachedStream> _cache = {};
  static final Map<String, Future<VideoStreamInfo?>> _inFlight = {};

  /// Max cached resolutions; oldest-used entries are evicted first.
  static const maxCacheEntries = 50;

  /// Entries this close to the URL's expiry are treated as stale: a stream
  /// that dies mid-video 403s, so refresh well before googlevideo does.
  static const expiryMargin = Duration(minutes: 30);

  /// Assumed lifetime when the URL carries no `expire=` parameter.
  static const assumedUrlLifetime = Duration(hours: 5);

  static String _cacheKey(String videoId, VideoQuality quality) =>
      '$videoId:${quality.name}';

  /// When a stream URL stops working: its `expire=` epoch-seconds query
  /// parameter when present, else [fetchedAt] + [assumedUrlLifetime].
  static DateTime urlExpiry(String url, DateTime fetchedAt) {
    final expire = Uri.tryParse(url)?.queryParameters['expire'];
    final secs = expire == null ? null : int.tryParse(expire);
    if (secs != null && secs > 0) {
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
    }
    return fetchedAt.add(assumedUrlLifetime);
  }

  /// Whether a cached [url] resolved at [fetchedAt] is still safe to hand out.
  static bool isFresh(String url, DateTime fetchedAt, DateTime now) =>
      now.isBefore(urlExpiry(url, fetchedAt).subtract(expiryMargin));

  /// Best effort video URL for [videoId] (muted player surface).
  static Future<VideoStreamInfo?> resolve(
    String videoId, {
    VideoQuality quality = VideoQuality.high,
  }) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    final key = _cacheKey(id, quality);
    final cached = _cache.remove(key);
    if (cached != null &&
        isFresh(cached.info.url, cached.fetchedAt, DateTime.now())) {
      _cache[key] = cached; // re-insert: now the most recently used
      return cached.info;
    }

    // Concurrent callers for the same id share one resolution.
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _resolveUncached(id, quality);
    _inFlight[key] = future;
    try {
      final info = await future;
      if (info != null) _put(key, info);
      return info;
    } finally {
      _inFlight.remove(key);
    }
  }

  static Future<VideoStreamInfo?> _resolveUncached(
      String id, VideoQuality quality) async {
    final viaNewPipe = await _viaNewPipe(id, quality);
    if (viaNewPipe != null) return viaNewPipe;
    return _viaExplode(id, quality);
  }

  static void _put(String key, VideoStreamInfo info) {
    _cache.remove(key);
    _cache[key] = _CachedStream(info, DateTime.now());
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void clearCache([String? videoId]) {
    if (videoId == null) {
      _cache.clear();
      return;
    }
    final id = videoId.trim();
    _cache.removeWhere((k, _) => k == id || k.startsWith('$id:'));
  }

  static Future<VideoStreamInfo?> _viaNewPipe(
    String videoId,
    VideoQuality quality,
  ) async {
    if (!Platform.isAndroid) return null;
    try {
      final auth = StreamProvider.authHeadersFromSession();
      final args = <String, dynamic>{'videoId': videoId};
      if (auth != null) {
        if (auth['cookie'] != null) args['cookie'] = auth['cookie'];
        if (auth['authorization'] != null) {
          args['authorization'] = auth['authorization'];
        }
      }
      final res = await _newPipeChannel
          .invokeMethod<String>('getMuxedVideoStreams', args);
      if (res == null) return null;
      final list = jsonDecode(res) as List;
      final parsed = <VideoStreamInfo>[];
      for (final e in list) {
        if (e is! Map) continue;
        final url = '${e['url'] ?? ''}'.trim();
        if (url.isEmpty) continue;
        parsed.add(VideoStreamInfo(
          url: url,
          width: _asInt(e['width']),
          height: _asInt(e['height']),
          itag: _asInt(e['itag']),
          mimeType: '${e['mimeType'] ?? ''}',
          hasAudio: e['hasAudio'] != false,
        ));
      }
      return pickBestForPlayer(parsed, quality: quality);
    } catch (e) {
      printERROR('NewPipe muxed video failed ($videoId): $e');
    }
    return null;
  }

  static Future<VideoStreamInfo?> _viaExplode(
    String videoId,
    VideoQuality quality,
  ) async {
    final yt = YoutubeExplode();
    try {
      StreamManifest? res;
      Object? lastError;
      for (final clients in [
        [YoutubeApiClient.androidSdkless, YoutubeApiClient.ios],
        [YoutubeApiClient.android],
      ]) {
        try {
          res = await yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: clients,
            requireWatchPage: false,
          );
          if (res.muxed.isNotEmpty || res.videoOnly.isNotEmpty) break;
        } catch (e) {
          lastError = e;
        }
      }
      if (res == null || (res.muxed.isEmpty && res.videoOnly.isEmpty)) {
        if (lastError != null) printERROR('Explode video streams: $lastError');
        return null;
      }
      final parsed = <VideoStreamInfo>[
        ...res.videoOnly.map((e) => VideoStreamInfo(
              url: e.url.toString(),
              width: e.videoResolution.width,
              height: e.videoResolution.height,
              itag: e.tag,
              mimeType: e.container.name,
              hasAudio: false,
            )),
        ...res.muxed.map((e) => VideoStreamInfo(
              url: e.url.toString(),
              width: e.videoResolution.width,
              height: e.videoResolution.height,
              itag: e.tag,
              mimeType: e.container.name,
              hasAudio: true,
            )),
      ];
      return pickBestForPlayer(parsed, quality: quality);
    } catch (e) {
      printERROR('Explode video failed ($videoId): $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Prefer video-only, then the best height within the tier cap
  /// (High ≤1080p — full quality; Low ≤480p), then a codec the device
  /// likely hardware-decodes (H.264 > VP9 > AV1). Exposed for unit tests.
  static VideoStreamInfo? pickBestForPlayer(
    List<VideoStreamInfo> streams, {
    VideoQuality quality = VideoQuality.high,
  }) {
    if (streams.isEmpty) return null;

    // Video mode supplies its own audio track to the engine, so muxed
    // audio would just be decoded and discarded — take video-only when
    // any exists.
    final videoOnly = streams.where((s) => !s.hasAudio).toList();
    var pool = videoOnly.isNotEmpty ? videoOnly : streams;

    final maxH = quality == VideoQuality.high ? 1080 : 480;
    final capped = pool.where((s) => s.height > 0 && s.height <= maxH).toList();
    if (capped.isNotEmpty) {
      pool = capped;
    }

    final ranked = List<VideoStreamInfo>.from(pool)
      ..sort((a, b) {
        final h = b.height.compareTo(a.height);
        if (h != 0) return h;
        return _codecBonus(b).compareTo(_codecBonus(a));
      });
    return ranked.first;
  }

  static int _codecBonus(VideoStreamInfo s) {
    final mime = (s.mimeType ?? '').toLowerCase();
    // Prefer H.264/MP4 hardware paths over VP9/WebM, and both over AV1.
    var sc = 0;
    if (mime.contains('mp4') ||
        mime.contains('avc') ||
        mime.contains('h264') ||
        mime == 'mp4') {
      sc += 20;
    }
    if (mime.contains('av01') || mime.contains('av1')) {
      sc -= 15;
    }
    return sc;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
