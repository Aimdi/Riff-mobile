import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// BPM + musical key for Mix mode (Camelot-friendly).
class TrackAnalysis {
  const TrackAnalysis({
    required this.bpm,
    required this.keyName,
    required this.scale,
    required this.camelot,
  });

  final int bpm;
  final String keyName; // e.g. C, F#
  final String scale; // major | minor
  final String camelot; // e.g. 8B

  Map<String, dynamic> toJson() => {
        'bpm': bpm,
        'keyName': keyName,
        'scale': scale,
        'camelot': camelot,
      };

  factory TrackAnalysis.fromJson(Map<String, dynamic> j) => TrackAnalysis(
        bpm: (j['bpm'] as num?)?.round() ?? 0,
        keyName: '${j['keyName'] ?? ''}',
        scale: '${j['scale'] ?? ''}',
        camelot: '${j['camelot'] ?? ''}',
      );
}

/// Looks up tempo/key via MusicBrainz + AcousticBrainz (free, no API key).
/// Results are cached in Hive. Coverage isn't perfect — unknown tracks show "—".
class TrackAnalysisService extends GetxController {
  TrackAnalysisService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'RiffMobile/1.0 (https://github.com/Aimdi/Riff-mobile)',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;
  static const _boxName = 'TrackAnalysisCache';
  static const _uaPause = Duration(milliseconds: 1100);

  DateTime _lastMbCall = DateTime.fromMillisecondsSinceEpoch(0);

  Box get _box {
    if (!Hive.isBoxOpen(_boxName)) {
      throw StateError('TrackAnalysisCache box not open');
    }
    return Hive.box(_boxName);
  }

  static String cacheKey(String title, String artist) {
    final raw = '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  TrackAnalysis? cached(String title, String artist) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final raw = _box.get(cacheKey(title, artist));
    if (raw is Map) {
      return TrackAnalysis.fromJson(Map<String, dynamic>.from(raw));
    }
    if (raw == 'miss') return null;
    return null;
  }

  bool hasMiss(String title, String artist) {
    if (!Hive.isBoxOpen(_boxName)) return false;
    return _box.get(cacheKey(title, artist)) == 'miss';
  }

  Future<TrackAnalysis?> analyze({
    required String title,
    required String artist,
  }) async {
    final t = title.trim();
    final a = artist.trim();
    if (t.isEmpty) return null;

    final key = cacheKey(t, a);
    if (Hive.isBoxOpen(_boxName)) {
      final hit = _box.get(key);
      if (hit is Map) {
        return TrackAnalysis.fromJson(Map<String, dynamic>.from(hit));
      }
      if (hit == 'miss') return null;
    }

    try {
      await _throttleMb();
      final mbid = await _musicBrainzRecordingId(t, a);
      if (mbid == null) {
        await _storeMiss(key);
        return null;
      }
      final analysis = await _acousticBrainz(mbid);
      if (analysis == null) {
        await _storeMiss(key);
        return null;
      }
      if (Hive.isBoxOpen(_boxName)) {
        await _box.put(key, analysis.toJson());
      }
      return analysis;
    } catch (_) {
      return null;
    }
  }

  /// Analyze many tracks sequentially (respects MB rate limit).
  Future<Map<String, TrackAnalysis>> analyzeMany(
    List<({String id, String title, String artist})> tracks, {
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <String, TrackAnalysis>{};
    for (var i = 0; i < tracks.length; i++) {
      final tr = tracks[i];
      final a = await analyze(title: tr.title, artist: tr.artist);
      if (a != null) out[tr.id] = a;
      onProgress?.call(i + 1, tracks.length);
    }
    return out;
  }

  Future<void> _storeMiss(String key) async {
    if (Hive.isBoxOpen(_boxName)) await _box.put(key, 'miss');
  }

  Future<void> _throttleMb() async {
    final wait = _uaPause - DateTime.now().difference(_lastMbCall);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastMbCall = DateTime.now();
  }

  Future<String?> _musicBrainzRecordingId(String title, String artist) async {
    final q = artist.isEmpty
        ? 'recording:"${_esc(title)}"'
        : 'recording:"${_esc(title)}" AND artist:"${_esc(artist)}"';
    final res = await _dio.get(
      'https://musicbrainz.org/ws/2/recording/',
      queryParameters: {'query': q, 'fmt': 'json', 'limit': 5},
    );
    if (res.statusCode != 200 || res.data is! Map) return null;
    final list = (res.data as Map)['recordings'];
    if (list is! List || list.isEmpty) return null;
    return '${list.first['id']}';
  }

  Future<TrackAnalysis?> _acousticBrainz(String mbid) async {
    final res = await _dio.get(
      'https://acousticbrainz.org/api/v1/$mbid/low-level',
      options: Options(validateStatus: (s) => s != null && s < 500),
    );
    if (res.statusCode != 200 || res.data is! Map) return null;
    final data = Map<String, dynamic>.from(res.data as Map);
    final rhythm = data['rhythm'];
    final tonal = data['tonal'];
    if (rhythm is! Map || tonal is! Map) return null;
    final bpmRaw = rhythm['bpm'];
    final bpm = bpmRaw is num ? bpmRaw.round() : int.tryParse('$bpmRaw') ?? 0;
    final keyName = '${tonal['key_key'] ?? ''}'.trim();
    final scale = '${tonal['key_scale'] ?? ''}'.trim().toLowerCase();
    if (bpm < 40 || bpm > 240 || keyName.isEmpty) return null;
    final camelot = toCamelot(keyName, scale);
    return TrackAnalysis(
      bpm: bpm,
      keyName: keyName,
      scale: scale,
      camelot: camelot,
    );
  }

  static String _esc(String s) => s.replaceAll('"', '\\"');

  /// Camelot Wheel code for harmonic mixing (e.g. 8B = C major).
  static String toCamelot(String key, String scale) {
    const majors = {
      'C': '8B',
      'G': '9B',
      'D': '10B',
      'A': '11B',
      'E': '12B',
      'B': '1B',
      'F#': '2B',
      'Gb': '2B',
      'C#': '3B',
      'Db': '3B',
      'G#': '4B',
      'Ab': '4B',
      'D#': '5B',
      'Eb': '5B',
      'A#': '6B',
      'Bb': '6B',
      'F': '7B',
    };
    const minors = {
      'A': '8A',
      'E': '9A',
      'B': '10A',
      'F#': '11A',
      'Gb': '11A',
      'C#': '12A',
      'Db': '12A',
      'G#': '1A',
      'Ab': '1A',
      'D#': '2A',
      'Eb': '2A',
      'A#': '3A',
      'Bb': '3A',
      'F': '4A',
      'C': '5A',
      'G': '6A',
      'D': '7A',
    };
    final k = key.replaceAll('♯', '#').replaceAll('♭', 'b');
    final map = scale.startsWith('min') ? minors : majors;
    return map[k] ?? map[k.replaceAll('b', '')] ?? '—';
  }

  /// Harmonic distance on the Camelot wheel (0 = perfect match).
  static int camelotDistance(String a, String b) {
    final pa = _parseCamelot(a);
    final pb = _parseCamelot(b);
    if (pa == null || pb == null) return 99;
    final numDist = (pa.$1 - pb.$1).abs();
    final ring = numDist > 6 ? 12 - numDist : numDist;
    final modePenalty = pa.$2 == pb.$2 ? 0 : 1;
    return ring + modePenalty;
  }

  static (int, String)? _parseCamelot(String c) {
    final m = RegExp(r'^(\d{1,2})([AB])$', caseSensitive: false).firstMatch(c);
    if (m == null) return null;
    return (int.parse(m.group(1)!), m.group(2)!.toUpperCase());
  }
}
