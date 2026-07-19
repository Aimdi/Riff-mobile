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

    return MediaItem(
        id: json["videoId"],
        title: json["title"],
        duration: json['duration'] != null
            ? Duration(seconds: json['duration'])
            : toDuration(json['length']),
        album: album != null ? album['name'] : null,
        artist: artistName,
        // Use extraHigh so full-player / notification art stays sharp
        artUri: Uri.parse(Thumbnail(json["thumbnails"][0]['url']).extraHigh),
        extras: {
          'url': json['url'] ?? url,
          'length': json['length'],
          'album': album,
          'artists': json['artists'],
          'date': json['date'],
          'trackDetails': json['trackDetails'],
          'year': json['year']
        });
  }

  static Duration? toDuration(String? time) {
    if (time == null) {
      return null;
    }

    // Podcast-style durations: "25 min", "1 hr 12 min"
    final lower = time.toLowerCase();
    if (lower.contains('min') || lower.contains('hr') || lower.contains('sec')) {
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
        'year': mediaItem.extras?['year']
      };
}
