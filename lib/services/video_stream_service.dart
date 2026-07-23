import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/services/stream_service.dart';
import '/utils/helper.dart';

/// In-player muted video surface quality.
///
/// Both tiers prefer **video-only** H.264 so ExoPlayer does not decode a
/// discarded muxed audio track. High caps at 720p to keep decode cost sane.
enum VideoQuality {
  low,
  high,
}

/// Video URL for the muted in-player surface.
///
/// Audio stays on just_audio. Prefer low-res **video-only** streams so ExoPlayer
/// does not also decode a discarded muxed audio track (a major lag source).
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

/// One video-only stream candidate for mpv video mode.
class VideoOnlyStream {
  VideoOnlyStream({
    required this.url,
    required this.height,
    this.fps = 30,
    this.mimeType = '',
  });
  final String url;
  final int height;
  final int fps;
  final String mimeType;
}

class VideoStreamService {
  VideoStreamService._();

  static const _newPipeChannel = MethodChannel('riff/newpipe');
  static final Map<String, VideoStreamInfo> _cache = {};

  static String _cacheKey(String videoId, VideoQuality quality) =>
      '$videoId:${quality.name}';

  /// Best effort video URL for [videoId] (muted player surface).
  static Future<VideoStreamInfo?> resolve(
    String videoId, {
    VideoQuality quality = VideoQuality.high,
  }) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    final key = _cacheKey(id, quality);
    final cached = _cache[key];
    if (cached != null) return cached;

    final viaNewPipe = await _viaNewPipeMuxed(id, quality);
    if (viaNewPipe != null) {
      _cache[key] = viaNewPipe;
      return viaNewPipe;
    }

    final viaExplode = await _viaExplodeMuxed(id, quality);
    if (viaExplode != null) {
      _cache[key] = viaExplode;
      return viaExplode;
    }
    return null;
  }

  /// Best video-only stream at or below [maxHeight] (1080p default) for mpv
  /// video mode. Audio is paired separately from the music pipeline.
  static Future<VideoOnlyStream?> bestVideoOnly(String videoId,
      {int maxHeight = 1080}) async {
    final native = await _viaNewPipeVideoOnly(videoId);
    final streams = native ?? await _viaExplodeVideoOnly(videoId);
    if (streams == null || streams.isEmpty) return null;
    return _pickVideoOnly(streams, maxHeight);
  }

  static void clearCache([String? videoId]) {
    if (videoId == null) {
      _cache.clear();
      return;
    }
    final id = videoId.trim();
    _cache.removeWhere((k, _) => k == id || k.startsWith('$id:'));
  }

  /// Highest resolution wins; at equal height prefer higher fps, then a
  /// codec the device likely hardware-decodes (avc/vp9 over av1).
  static VideoOnlyStream _pickVideoOnly(
      List<VideoOnlyStream> streams, int maxHeight) {
    int codecRank(String mime) {
      final m = mime.toLowerCase();
      if (m.contains('avc') || m.contains('h264') || m.contains('mp4')) {
        return 2;
      }
      if (m.contains('vp9') || m.contains('vp09') || m.contains('webm')) {
        return 1;
      }
      return 0; // av01 and friends
    }

    final within =
        streams.where((s) => s.height > 0 && s.height <= maxHeight).toList();
    final pool = within.isEmpty ? streams : within;
    pool.sort((a, b) {
      final h = a.height.compareTo(b.height);
      if (h != 0) return h;
      final f = a.fps.compareTo(b.fps);
      if (f != 0) return f;
      return codecRank(a.mimeType).compareTo(codecRank(b.mimeType));
    });
    return pool.last;
  }

  static Map<String, dynamic> _authArgs(String videoId) {
    final args = <String, dynamic>{'videoId': videoId};
    final auth = StreamProvider.authHeadersFromSession();
    if (auth != null) {
      if (auth['cookie'] != null) args['cookie'] = auth['cookie'];
      if (auth['authorization'] != null) {
        args['authorization'] = auth['authorization'];
      }
    }
    return args;
  }

  static Future<VideoStreamInfo?> _viaNewPipeMuxed(
    String videoId,
    VideoQuality quality,
  ) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _newPipeChannel
          .invokeMethod<String>('getMuxedVideoStreams', _authArgs(videoId));
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

  static Future<List<VideoOnlyStream>?> _viaNewPipeVideoOnly(
      String videoId) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _newPipeChannel
          .invokeMethod<String>('getVideoStreams', _authArgs(videoId));
      if (res == null) return null;
      final list = jsonDecode(res) as List;
      final streams = list
          .whereType<Map>()
          .where((e) => (e['url'] ?? '').toString().isNotEmpty)
          .map((e) => VideoOnlyStream(
                url: e['url'].toString(),
                height: (e['height'] as num?)?.toInt() ?? 0,
                fps: (e['fps'] as num?)?.toInt() ?? 30,
                mimeType: (e['mimeType'] ?? '').toString(),
              ))
          .toList();
      return streams.isEmpty ? null : streams;
    } catch (e) {
      printERROR('NewPipe video resolver failed ($videoId): $e');
      return null;
    }
  }

  static Future<VideoStreamInfo?> _viaExplodeMuxed(
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

  static Future<List<VideoOnlyStream>?> _viaExplodeVideoOnly(
      String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      return manifest.videoOnly
          .map((s) => VideoOnlyStream(
                url: s.url.toString(),
                height: s.videoResolution.height,
                fps: s.framerate.framesPerSecond.round(),
                mimeType: '${s.codec.mimeType}; codecs=${s.videoCodec}',
              ))
          .toList();
    } catch (e) {
      printERROR('Explode video resolver failed ($videoId): $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Prefer video-only (no discarded audio decode), then quality-tier height.
  /// Exposed for unit tests.
  static VideoStreamInfo? pickBestForPlayer(
    List<VideoStreamInfo> streams, {
    VideoQuality quality = VideoQuality.low,
  }) {
    if (streams.isEmpty) return null;

    // Mute surface never needs muxed A/V — drop muxed whenever any video-only
    // candidate exists (biggest lag win without lowering resolution).
    final videoOnly = streams.where((s) => !s.hasAudio).toList();
    var pool = videoOnly.isNotEmpty ? videoOnly : streams;

    // Cap height per tier so we never "upgrade" into hitchy 1080p+ when a
    // ≤720 (High) / ≤360 (Low) option exists.
    final maxH = quality == VideoQuality.high ? 720 : 360;
    final capped = pool.where((s) => s.height > 0 && s.height <= maxH).toList();
    if (capped.isNotEmpty) {
      pool = capped;
    }

    final score =
        quality == VideoQuality.high ? _scoreHigh : _scoreLow;

    final ranked = List<VideoStreamInfo>.from(pool)
      ..sort((a, b) {
        final d = score(b).compareTo(score(a));
        if (d != 0) return d;
        // High: prefer taller when scores tie; Low: prefer shorter.
        return quality == VideoQuality.high
            ? b.height.compareTo(a.height)
            : a.height.compareTo(b.height);
      });
    return ranked.first;
  }

  /// Battery/CPU-friendly: 144–240p video-only H.264.
  static int _scoreLow(VideoStreamInfo s) {
    var sc = 0;
    final h = s.height;
    if (h > 0 && h <= 144) {
      sc += 100;
    } else if (h <= 240) {
      sc += 90;
    } else if (h <= 360) {
      sc += 55;
    } else if (h <= 480) {
      sc += 25;
    } else if (h <= 720) {
      sc += 5;
    } else {
      sc -= 40;
    }

    // Video-only avoids decoding muxed AAC that we immediately mute.
    if (!s.hasAudio && h > 0 && h <= 360) {
      sc += 45;
    } else if (!s.hasAudio && h > 360) {
      sc += 10;
    } else if (s.hasAudio) {
      sc -= 25;
    }

    sc += _codecBonus(s);
    return sc;
  }

  /// Sharper picture without 1080p+ or muxed audio decode: prefer ≤720p
  /// video-only H.264 (480–720 sweet spot).
  static int _scoreHigh(VideoStreamInfo s) {
    var sc = 0;
    final h = s.height;
    if (h > 720) {
      // 1080p+ is a common hitch source on mid-range devices.
      sc -= 50;
    } else if (h >= 720) {
      sc += 100;
    } else if (h >= 480) {
      sc += 88;
    } else if (h >= 360) {
      sc += 55;
    } else if (h >= 240) {
      sc += 30;
    } else if (h > 0) {
      sc += 10;
    }

    // Video-only is the main lag win at any height.
    if (!s.hasAudio) {
      sc += 60;
    } else {
      sc -= 30;
    }

    sc += _codecBonus(s);
    return sc;
  }

  static int _codecBonus(VideoStreamInfo s) {
    final mime = (s.mimeType ?? '').toLowerCase();
    // Prefer H.264/MP4 hardware paths over VP9/WebM on mid-range Android.
    var sc = 0;
    if (mime.contains('mp4') ||
        mime.contains('avc') ||
        mime.contains('h264') ||
        mime == 'mp4') {
      sc += 20;
    }
    if (mime.contains('webm') ||
        mime.contains('vp9') ||
        mime.contains('vp09') ||
        mime.contains('av01') ||
        mime.contains('av1')) {
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
