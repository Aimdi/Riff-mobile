import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/utils/helper.dart';

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

class VideoStreamService {
  VideoStreamService._();

  static const _newPipeChannel = MethodChannel('riff/newpipe');
  static final Map<String, VideoStreamInfo> _cache = {};

  /// Best effort video URL for [videoId] (muted player surface).
  static Future<VideoStreamInfo?> resolve(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return null;
    final cached = _cache[id];
    if (cached != null) return cached;

    final viaNewPipe = await _viaNewPipe(id);
    if (viaNewPipe != null) {
      _cache[id] = viaNewPipe;
      return viaNewPipe;
    }

    final viaExplode = await _viaExplode(id);
    if (viaExplode != null) {
      _cache[id] = viaExplode;
      return viaExplode;
    }
    return null;
  }

  static void clearCache([String? videoId]) {
    if (videoId == null) {
      _cache.clear();
    } else {
      _cache.remove(videoId);
    }
  }

  static Future<VideoStreamInfo?> _viaNewPipe(String videoId) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _newPipeChannel
          .invokeMethod<String>('getMuxedVideoStreams', {'videoId': videoId});
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
      return pickBestForPlayer(parsed);
    } catch (e) {
      printERROR('NewPipe muxed video failed ($videoId): $e');
    }
    return null;
  }

  static Future<VideoStreamInfo?> _viaExplode(String videoId) async {
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
      return pickBestForPlayer(parsed);
    } catch (e) {
      printERROR('Explode video failed ($videoId): $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Prefer low-res video-only (no discarded audio decode), then low muxed.
  /// Exposed for unit tests.
  static VideoStreamInfo? pickBestForPlayer(List<VideoStreamInfo> streams) {
    if (streams.isEmpty) return null;

    int score(VideoStreamInfo s) {
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
      }

      final mime = (s.mimeType ?? '').toLowerCase();
      // Prefer H.264/MP4 hardware paths over VP9/WebM on mid-range Android.
      if (mime.contains('mp4') ||
          mime.contains('avc') ||
          mime.contains('h264') ||
          mime == 'mp4') {
        sc += 12;
      }
      if (mime.contains('webm') ||
          mime.contains('vp9') ||
          mime.contains('vp09')) {
        sc -= 8;
      }
      return sc;
    }

    final ranked = List<VideoStreamInfo>.from(streams)
      ..sort((a, b) {
        final d = score(b).compareTo(score(a));
        if (d != 0) return d;
        return a.height.compareTo(b.height);
      });
    return ranked.first;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
