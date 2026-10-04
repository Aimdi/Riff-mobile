import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// A song Shazam recognised.
class RecognizedSong {
  const RecognizedSong({
    required this.title,
    required this.artist,
    this.coverUrl,
    this.album,
    this.label,
    this.released,
    this.lyrics,
    this.shazamUrl,
    this.recognizedAt,
  });

  final String title;
  final String artist;
  final String? coverUrl;
  final String? album;
  final String? label;
  final String? released;
  final String? lyrics;
  final String? shazamUrl;
  final DateTime? recognizedAt;

  /// "Title Artist", for a YouTube Music search.
  String get query => '$title $artist'.trim();

  RecognizedSong copyWith({DateTime? recognizedAt}) => RecognizedSong(
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        album: album,
        label: label,
        released: released,
        lyrics: lyrics,
        shazamUrl: shazamUrl,
        recognizedAt: recognizedAt ?? this.recognizedAt,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        if (coverUrl != null) 'cover': coverUrl,
        if (album != null) 'album': album,
        if (label != null) 'label': label,
        if (released != null) 'released': released,
        if (shazamUrl != null) 'url': shazamUrl,
        if (recognizedAt != null) 'at': recognizedAt!.millisecondsSinceEpoch,
      };

  static RecognizedSong? fromJson(dynamic j) {
    if (j is! Map) return null;
    final title = j['title'], artist = j['artist'];
    if (title is! String || artist is! String) return null;
    String? s(String k) => j[k] is String ? j[k] as String : null;
    final at = j['at'];
    return RecognizedSong(
      title: title,
      artist: artist,
      coverUrl: s('cover'),
      album: s('album'),
      label: s('label'),
      released: s('released'),
      shazamUrl: s('url'),
      recognizedAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }

  /// Reads Shazam's tag response (`track` is absent when nothing matched).
  static RecognizedSong? fromShazamResponse(dynamic body) {
    if (body is! Map) return null;
    final track = body['track'];
    if (track is! Map) return null;
    final title = track['title'], artist = track['subtitle'];
    if (title is! String || title.isEmpty || artist is! String) return null;
    final sections = track['sections'] is List ? track['sections'] as List : [];
    Map? section(String type) => sections
        .whereType<Map>()
        .cast<Map?>()
        .firstWhere((s) => '${s!['type']}'.toUpperCase() == type,
            orElse: () => null);
    String? meta(String name) {
      final song = section('SONG');
      final list = song?['metadata'];
      if (list is! List) return null;
      for (final m in list.whereType<Map>()) {
        if ('${m['title']}'.toUpperCase() == name && m['text'] is String) {
          return m['text'] as String;
        }
      }
      return null;
    }

    final lyricsText = section('LYRICS')?['text'];
    final images = track['images'] is Map ? track['images'] as Map : const {};
    final cover = images['coverarthq'] ?? images['coverart'];
    return RecognizedSong(
      title: title,
      artist: artist,
      coverUrl: cover is String && cover.isNotEmpty ? cover : null,
      album: meta('ALBUM'),
      label: meta('LABEL'),
      released: meta('RELEASED'),
      lyrics: lyricsText is List ? lyricsText.join('\n') : null,
      shazamUrl: track['url'] is String ? track['url'] as String : null,
    );
  }
}

/// Shazam's public tag endpoint, called the way Audire does
/// (https://github.com/alexmercerind/audire, GPL-3.0): a signature, a
/// random device identity per request, no account.
class ShazamClient {
  ShazamClient({Dio? dio, math.Random? random})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _random = random ?? math.Random();

  final Dio _dio;
  final math.Random _random;

  static const _base =
      'https://amp.shazam.com/discovery/v5/en/US/android/-/tag';

  static const _userAgents = [
    'Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)',
    'Dalvik/2.1.0 (Linux; U; Android 5.1.1; SM-P905V Build/LMY47X)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)',
    'Dalvik/2.1.0 (Linux; U; Android 5.0; SM-G900F Build/LRX21T)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G928F Build/MMB29K)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; D6603 Build/23.5.A.0.570)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0; LG-H815 Build/MRA58K)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G930F Build/MMB29K)',
  ];

  static const _timezones = [
    'Europe/Amsterdam',
    'Europe/Berlin',
    'Europe/Brussels',
    'Europe/Dublin',
    'Europe/Helsinki',
    'Europe/Lisbon',
    'Europe/London',
    'Europe/Madrid',
    'Europe/Oslo',
    'Europe/Paris',
    'Europe/Prague',
    'Europe/Rome',
    'Europe/Stockholm',
    'Europe/Vienna',
    'Europe/Warsaw',
    'Europe/Zurich',
  ];

  /// Request body for one signature covering [sampleMs] of audio.
  Map<String, dynamic> requestBody(String signatureUri, int sampleMs,
      {int? timestamp}) {
    final ts =
        timestamp ?? (DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
    return {
      'geolocation': {
        'altitude': _random.nextDouble() * 400 + 100,
        'latitude': _random.nextDouble() * 180 - 90,
        'longitude': _random.nextDouble() * 360 - 180,
      },
      'signature': {
        'samplems': sampleMs,
        'timestamp': ts,
        'uri': signatureUri,
      },
      'timestamp': ts,
      'timezone': _timezones[_random.nextInt(_timezones.length)],
    };
  }

  /// Asks Shazam what [signatureUri] is. Null when it doesn't know.
  Future<RecognizedSong?> identify(String signatureUri, int sampleMs) async {
    final name = '${_random.nextInt(1 << 31)}${_random.nextInt(1 << 17)}';
    final url = '$_base/${uuidV5(_dnsNamespace, name)}/'
        '${uuidV5(_urlNamespace, name)}';
    final res = await _dio.post(
      url,
      queryParameters: const {
        'sync': 'true',
        'webv3': 'true',
        'sampling': 'true',
        'connected': '',
        'shazamapiversion': 'v3',
        'sharehub': 'true',
        'video': 'v3',
      },
      data: jsonEncode(requestBody(signatureUri, sampleMs)),
      options: Options(
        headers: {
          'User-Agent': _userAgents[_random.nextInt(_userAgents.length)],
          'Content-Language': 'en_US',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
      ),
    );
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    return RecognizedSong.fromShazamResponse(data);
  }

  static final _dnsNamespace =
      _uuidBytes('6ba7b810-9dad-11d1-80b4-00c04fd430c8');
  static final _urlNamespace =
      _uuidBytes('6ba7b811-9dad-11d1-80b4-00c04fd430c8');

  static Uint8List _uuidBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    return Uint8List.fromList([
      for (var i = 0; i < 32; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16)
    ]);
  }

  /// RFC 4122 name-based (SHA-1, version 5) UUID.
  static String uuidV5(Uint8List namespace, String name) {
    final hash = sha1.convert([...namespace, ...utf8.encode(name)]).bytes;
    final b = Uint8List.fromList(hash.sublist(0, 16));
    b[6] = (b[6] & 0x0f) | 0x50;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Exposed for tests.
  static Uint8List get dnsNamespace => _dnsNamespace;
}
