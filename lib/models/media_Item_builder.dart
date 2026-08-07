// ignore_for_file: file_names

import 'package:audio_service/audio_service.dart';
import '../models/thumbnail.dart';

class MediaItemBuilder {
  static MediaItem fromJson(dynamic json, {String? url}) {
    String? artistName;
    if (json['artists'] != null) {
      artistName =
          json['artists']?.map((e) => e['name']).toList().join(', ').toString();
    }

    Map? album;
    if (json['album'] != null) {
      if (json['album']['id'] != null) {
        album = json['album'];
      }
    }

    // Prefer the largest thumbnail YTM returned, then upscale to player quality.
    // Always prefer square cover art (lh3/ggpht) over 16:9 i.ytimg video frames
    // when the feed offers both — matches RiPlay's crisp square song rows. A
    // pure music video with only a 16:9 frame still falls back to that frame.
    final art = Thumbnail.bestUrl(
      json["thumbnails"],
      target: 'extraHigh',
      fallback: _fallbackThumbUrl(json),
      preferSquare: true,
    );

    // Flag podcast episodes so the player can show the podcast transport
    // (Shownotes, speed, ±skip) instead of the music one.
    final isPodcast = json['isPodcast'] == true ||
        (json['videoType']?.toString() ?? '').contains('PODCAST') ||
        (json['videoId']?.toString() ?? '').startsWith('podcast_');

    return MediaItem(
        id: json["videoId"],
        title: json["title"],
        duration: json['duration'] != null
            ? Duration(seconds: json['duration'])
            : toDuration(json['length']),
        album: album != null ? album['name'] : null,
        artist: artistName,
        artUri: art.isNotEmpty ? Uri.parse(art) : null,
        extras: {
          'url': json['url'] ?? url,
          'length': json['length'],
          'album': album,
          'artists': json['artists'],
          'date': json['date'],
          'pubDateMs': json['pubDateMs'] ?? _pubDateMsFromDate(json['date']),
          'trackDetails': json['trackDetails'],
          'year': json['year'],
          'isPodcast': isPodcast,
          'description': json['description'],
          'videoType': json['videoType'],
          'resultType': json['resultType'],
          if (json['showVideo'] != null) 'showVideo': json['showVideo'],
          if (json['podcastSource'] != null)
            'podcastSource': json['podcastSource'],
          // Audiobookshelf bookkeeping. Session save/restore round-trips every
          // queue item through this builder, and dropping these keys leaves a
          // restored audiobook playable but permanently unable to report its
          // position to the server (see AudiobookProgressService).
          if (json['streamSource'] != null) 'streamSource': json['streamSource'],
          if (json['absItemId'] != null) 'absItemId': json['absItemId'],
          if (json['absSessionId'] != null)
            'absSessionId': json['absSessionId'],
          if (json['absTrackIndex'] != null)
            'absTrackIndex': json['absTrackIndex'],
          if (json['absStartOffsetSec'] != null)
            'absStartOffsetSec': json['absStartOffsetSec'],
          if (json['discoveryReason'] != null)
            'discoveryReason': json['discoveryReason'],
          if (json['discoverySource'] != null)
            'discoverySource': json['discoverySource'],
          if (json['dailyMixId'] != null) 'dailyMixId': json['dailyMixId'],
          if (json['dailyMixTitle'] != null)
            'dailyMixTitle': json['dailyMixTitle'],
        });
  }

  /// Best-effort epoch ms from YTM relative dates ("2h ago", "3 days ago")
  /// or absolute strings.
  static int? _pubDateMsFromDate(dynamic raw) {
    if (raw is int) return raw;
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    final now = DateTime.now().toUtc();
    if (lower == 'today') return now.millisecondsSinceEpoch;
    if (lower == 'yesterday') {
      return now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    }
    final m = RegExp(
      r'^(\d+)\s*(seconds?|minutes?|hours?|days?|weeks?|months?|years?|secs?|mins?|hrs?|[smhdwy])\s*ago$',
    ).firstMatch(lower);
    if (m != null) {
      final n = int.parse(m.group(1)!);
      final unit = m.group(2)!;
      final d = switch (unit) {
        's' || 'sec' || 'secs' || 'second' || 'seconds' => Duration(seconds: n),
        'm' || 'min' || 'mins' || 'minute' || 'minutes' => Duration(minutes: n),
        'h' || 'hr' || 'hrs' || 'hour' || 'hours' => Duration(hours: n),
        'd' || 'day' || 'days' => Duration(days: n),
        'w' || 'week' || 'weeks' => Duration(days: n * 7),
        'month' || 'months' => Duration(days: n * 30),
        'y' || 'year' || 'years' => Duration(days: n * 365),
        _ => Duration.zero,
      };
      if (d > Duration.zero) {
        return now.subtract(d).millisecondsSinceEpoch;
      }
    }
    try {
      return DateTime.parse(s).toUtc().millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }
  }

  static String _fallbackThumbUrl(dynamic json) {
    final thumbs = json["thumbnails"];
    if (thumbs is List && thumbs.isNotEmpty) {
      final first = thumbs[0];
      if (first is Map && first['url'] != null) return first['url'].toString();
      if (first is String) return first;
    }
    if (json['thumbnailUrl'] != null) return json['thumbnailUrl'].toString();
    if (json['thumbnail'] != null) return json['thumbnail'].toString();
    return '';
  }

  static Duration? toDuration(String? time) {
    if (time == null) {
      return null;
    }

    // Podcast-style durations: "25 min", "1 hr 12 min"
    final lower = time.toLowerCase();
    if (lower.contains('min') ||
        lower.contains('hr') ||
        lower.contains('sec')) {
      int sec = 0;
      final hr = RegExp(r'(\d+)\s*hr').firstMatch(lower);
      final min = RegExp(r'(\d+)\s*min').firstMatch(lower);
      final s = RegExp(r'(\d+)\s*sec').firstMatch(lower);
      if (hr != null) sec += int.parse(hr.group(1)!) * 3600;
      if (min != null) sec += int.parse(min.group(1)!) * 60;
      if (s != null) sec += int.parse(s.group(1)!);
      if (sec > 0) return Duration(seconds: sec);
    }

    int sec = 0;
    final splitted = time.split(":");
    if (splitted.length == 3) {
      sec += int.parse(splitted[0]) * 3600 +
          int.parse(splitted[1]) * 60 +
          int.parse(splitted[2]);
    } else if (splitted.length == 2) {
      sec += int.parse(splitted[0]) * 60 + int.parse(splitted[1]);
    } else if (splitted.length == 1) {
      sec += int.tryParse(splitted[0]) ?? 0;
    }
    return Duration(seconds: sec);
  }

  static Map<String, dynamic> toJson(MediaItem mediaItem) => {
        "videoId": mediaItem.id,
        "title": mediaItem.title,
        'album': mediaItem.extras!['album'],
        'artists': mediaItem.extras!['artists'],
        'length': mediaItem.extras!['length'],
        'duration': mediaItem.duration?.inSeconds,
        'date': mediaItem.extras!['date'],
        'thumbnails': [
          {'url': mediaItem.artUri.toString()}
        ],
        'url': mediaItem.extras!['url'],
        'trackDetails': mediaItem.extras?['trackDetails'],
        'year': mediaItem.extras?['year'],
        'videoType': mediaItem.extras?['videoType'],
        'resultType': mediaItem.extras?['resultType'],
        'isPodcast': mediaItem.extras?['isPodcast'],
        'description': mediaItem.extras?['description'],
        'showVideo': mediaItem.extras?['showVideo'],
        'podcastSource': mediaItem.extras?['podcastSource'],
        // Keep the Audiobookshelf keys through the round-trip; only emitted
        // when present so ordinary songs serialize exactly as before.
        if (mediaItem.extras?['streamSource'] != null)
          'streamSource': mediaItem.extras?['streamSource'],
        if (mediaItem.extras?['absItemId'] != null)
          'absItemId': mediaItem.extras?['absItemId'],
        if (mediaItem.extras?['absSessionId'] != null)
          'absSessionId': mediaItem.extras?['absSessionId'],
        if (mediaItem.extras?['absTrackIndex'] != null)
          'absTrackIndex': mediaItem.extras?['absTrackIndex'],
        if (mediaItem.extras?['absStartOffsetSec'] != null)
          'absStartOffsetSec': mediaItem.extras?['absStartOffsetSec'],
        'pubDateMs': mediaItem.extras?['pubDateMs'],
        'discoveryReason': mediaItem.extras?['discoveryReason'],
        'discoverySource': mediaItem.extras?['discoverySource'],
        'dailyMixId': mediaItem.extras?['dailyMixId'],
        'dailyMixTitle': mediaItem.extras?['dailyMixTitle'],
      };
}
