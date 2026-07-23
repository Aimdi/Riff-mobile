import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '/utils/helper.dart';

/// Progressive / muxed video URL for in-player display.
///
/// Audio stays on just_audio; this URL drives a muted [VideoPlayer] synced to
/// the audio clock. Prefer ~480p progressive MP4 for reliability on mobile.
class VideoStreamInfo {
  const VideoStreamInfo({
    required this.url,
    required this.width,
    required this.height,
    this.itag,
    this.mimeType,
  });

  final String url;
  final int width;
  final int height;
  final int? itag;
  final String? mimeType;

  double get aspectRatio =>
      width > 0 && height > 0 ? width / height : 16 / 9;
}

class VideoStreamService {
  VideoStreamService._();

  static const _newPipeChannel = MethodChannel('riff/newpipe');
  static final Map<String, VideoStreamInfo> _cache = {};

  /// Best effort muxed/progressive video URL for [videoId].
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
        ));
      }
      return _pickBest(parsed);
    } catch (e) {
      printERROR('NewPipe muxed video failed ($videoId): $e');
      return null;
    }
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
          if (res.muxed.isNotEmpty) break;
        } catch (e) {
          lastError = e;
        }
      }
      if (res == null || res.muxed.isEmpty) {
        if (lastError != null) printERROR('Explode muxed: $lastError');
        return null;
      }
      final parsed = res.muxed
          .map((e) => VideoStreamInfo(
                url: e.url.toString(),
                width: e.videoResolution.width,
                height: e.videoResolution.height,
                itag: e.tag,
                mimeType: e.container.name,
              ))
          .toList();
      return _pickBest(parsed);
    } catch (e) {
      printERROR('Explode muxed video failed ($videoId): $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Prefer ~480p, then closest below 720p, never giant 1080+ on mobile data.
  static VideoStreamInfo? _pickBest(List<VideoStreamInfo> streams) {
    if (streams.isEmpty) return null;
    streams.sort((a, b) => a.height.compareTo(b.height));
    VideoStreamInfo? bestAtOrBelow(int maxH) {
      VideoStreamInfo? pick;
      for (final s in streams) {
        if (s.height <= maxH) pick = s;
      }
      return pick;
    }

    return bestAtOrBelow(480) ??
        bestAtOrBelow(720) ??
        bestAtOrBelow(360) ??
        streams.first;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}
