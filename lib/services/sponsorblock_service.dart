import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';

/// A single SponsorBlock segment (times in seconds).
class SponsorBlockSegment {
  const SponsorBlockSegment({
    required this.start,
    required this.end,
    required this.category,
    required this.actionType,
    required this.uuid,
  });

  final double start;
  final double end;
  final String category;
  final String actionType;
  final String uuid;

  bool contains(double seconds) =>
      seconds >= start && seconds < end && end > start + 0.15;

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'category': category,
        'actionType': actionType,
        'uuid': uuid,
      };

  factory SponsorBlockSegment.fromJson(Map json) => SponsorBlockSegment(
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
        category: json['category'] as String? ?? 'sponsor',
        actionType: json['actionType'] as String? ?? 'skip',
        uuid: json['uuid'] as String? ?? '',
      );
}

/// Community SponsorBlock client (https://sponsor.ajay.app).
///
/// Fetches skip segments for YouTube video IDs and exposes helpers used by the
/// player to auto-seek over sponsor / non-music sections.
class SponsorBlockService extends GetxService {
  static const defaultApi = 'https://sponsor.ajay.app/api';

  /// Categories that make sense for music / podcasts by default.
  static const defaultCategories = <String>[
    'sponsor',
    'selfpromo',
    'interaction',
    'intro',
    'outro',
    'preview',
    'music_offtopic',
  ];

  static const allCategories = <String>[
    'sponsor',
    'selfpromo',
    'interaction',
    'intro',
    'outro',
    'preview',
    'music_offtopic',
    'filler',
    'exclusive_access',
  ];

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {'user-agent': 'Riff-mobile/1.0 (SponsorBlock)'},
  ));

  final Map<String, List<SponsorBlockSegment>> _cache = {};

  bool get enabled {
    final box = Hive.box('AppPrefs');
    return box.get('sponsorBlockEnabled') ?? true;
  }

  set enabled(bool v) => Hive.box('AppPrefs').put('sponsorBlockEnabled', v);

  List<String> get categories {
    final box = Hive.box('AppPrefs');
    final raw = box.get('sponsorBlockCategories');
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    return List<String>.from(defaultCategories);
  }

  set categories(List<String> cats) =>
      Hive.box('AppPrefs').put('sponsorBlockCategories', cats);

  /// Load segments for [videoId], using in-memory cache when possible.
  Future<List<SponsorBlockSegment>> getSegments(String videoId) async {
    if (!enabled || videoId.isEmpty) return const [];
    if (_cache.containsKey(videoId)) return _cache[videoId]!;

    try {
      final cats = categories;
      final query = <String, dynamic>{
        'videoID': videoId,
        // API accepts either repeated category= or categories JSON array.
        'categories': jsonEncode(cats),
        'actionTypes': jsonEncode(['skip', 'mute']),
      };
      final res = await _dio.get('$defaultApi/skipSegments', queryParameters: query);
      final list = <SponsorBlockSegment>[];
      if (res.statusCode == 200 && res.data is List) {
        for (final item in res.data as List) {
          if (item is! Map) continue;
          final seg = item['segment'];
          if (seg is! List || seg.length < 2) continue;
          final action = (item['actionType'] ?? 'skip').toString();
          // Only auto-seek skip segments (mute handled separately if needed).
          if (action != 'skip') continue;
          final start = (seg[0] as num).toDouble();
          final end = (seg[1] as num).toDouble();
          if (end <= start) continue;
          list.add(SponsorBlockSegment(
            start: start,
            end: end,
            category: (item['category'] ?? 'sponsor').toString(),
            actionType: action,
            uuid: (item['UUID'] ?? item['uuid'] ?? '').toString(),
          ));
        }
        list.sort((a, b) => a.start.compareTo(b.start));
      }
      _cache[videoId] = list;
      printINFO('SponsorBlock: ${list.length} segments for $videoId');
      return list;
    } on DioException catch (e) {
      // 404 = no segments — normal.
      if (e.response?.statusCode == 404) {
        _cache[videoId] = const [];
        return const [];
      }
      printERROR('SponsorBlock fetch failed: $e');
      return const [];
    } catch (e) {
      printERROR('SponsorBlock error: $e');
      return const [];
    }
  }

  void clearCache([String? videoId]) {
    if (videoId == null) {
      _cache.clear();
    } else {
      _cache.remove(videoId);
    }
  }

  /// If [positionSec] falls inside a skippable segment, return seek target.
  Duration? seekTargetIfInSegment(
    List<SponsorBlockSegment> segments,
    double positionSec, {
    String? skipUuid,
  }) {
    for (final s in segments) {
      if (skipUuid != null && s.uuid == skipUuid) continue;
      if (s.contains(positionSec)) {
        // Jump slightly past the end to avoid re-triggering.
        return Duration(milliseconds: ((s.end + 0.05) * 1000).round());
      }
    }
    return null;
  }

  SponsorBlockSegment? activeSegment(
    List<SponsorBlockSegment> segments,
    double positionSec,
  ) {
    for (final s in segments) {
      if (s.contains(positionSec)) return s;
    }
    return null;
  }
}
