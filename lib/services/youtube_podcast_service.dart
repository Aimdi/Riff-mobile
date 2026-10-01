import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';

/// A YouTube podcast (a playlist the creator marked as a podcast).
class YtPodcastShow {
  const YtPodcastShow({
    required this.playlistId,
    required this.title,
    required this.author,
    this.authorId,
    required this.thumbnailUrl,
    this.episodeCountText,
    this.updatedText,
  });

  final String playlistId;
  final String title;
  final String author;
  final String? authorId;

  /// Largest square cover source.
  final String thumbnailUrl;

  /// Badge text as shown by YouTube, e.g. "831 episodes".
  final String? episodeCountText;

  /// e.g. "Updated 2 days ago".
  final String? updatedText;

  Map<String, dynamic> toJson() => {
        'playlistId': playlistId,
        'title': title,
        'author': author,
        'authorId': authorId,
        'thumbnailUrl': thumbnailUrl,
        'episodeCountText': episodeCountText,
        'updatedText': updatedText,
      };

  factory YtPodcastShow.fromJson(Map json) => YtPodcastShow(
        playlistId: '${json['playlistId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        author: '${json['author'] ?? ''}',
        authorId: json['authorId']?.toString(),
        thumbnailUrl: '${json['thumbnailUrl'] ?? ''}',
        episodeCountText: json['episodeCountText']?.toString(),
        updatedText: json['updatedText']?.toString(),
      );

  @override
  String toString() => 'YtPodcastShow($playlistId, $title)';
}

/// One page of episodes plus the token for the next page, if any.
class YtEpisodePage {
  const YtEpisodePage(this.episodes, this.continuation);

  final List<MediaItem> episodes;
  final String? continuation;
}

/// Parses InnerTube WEB responses for YouTube's podcast surfaces
/// (`FEpodcasts_destination`, search, a channel's Podcasts tab and the
/// `VL<playlistId>` show page). Pure functions, no network.
class YoutubePodcastParser {
  YoutubePodcastParser._();

  static const podcastType = 'LOCKUP_CONTENT_TYPE_PODCAST';
  static const videoType = 'LOCKUP_CONTENT_TYPE_VIDEO';

  static final _clock = RegExp(r'^\d+(:\d{1,2}){1,2}$');

  /// Podcast show lockups anywhere in the response body. Items without a
  /// visible author (a channel's own Podcasts tab) fall back to the
  /// channel described by the response's `channelMetadataRenderer`.
  static List<YtPodcastShow> showsFrom(Map json) {
    final channel = json['metadata']?['channelMetadataRenderer'];
    final fallbackAuthor = channel is Map ? channel['title']?.toString() : null;
    final fallbackId =
        channel is Map ? channel['externalId']?.toString() : null;

    final out = <YtPodcastShow>[];
    final seen = <String>{};
    _walk(_body(json), (key, value) {
      if (key != 'lockupViewModel' || value is! Map) return false;
      if (value['contentType'] != podcastType) return true;
      final show = _show(value, fallbackAuthor, fallbackId);
      if (show != null && seen.add(show.playlistId)) out.add(show);
      return true;
    });
    return out;
  }

  /// Popular episodes (`qgcCCAM=`): classic `videoRenderer` items.
  static List<MediaItem> popularEpisodesFrom(Map json) =>
      episodesFrom(json).episodes;

  /// Episodes from a show page, its continuation, or any feed of
  /// `videoRenderer` / `playlistVideoRenderer` / video lockups.
  static YtEpisodePage episodesFrom(Map json, {String? playlistId}) {
    final out = <MediaItem>[];
    final seen = <String>{};
    String? sibling;
    String? any;

    MediaItem? parse(String key, dynamic value) {
      if (value is! Map) return null;
      return switch (key) {
        'lockupViewModel' => value['contentType'] == videoType
            ? _fromVideoLockup(value, playlistId)
            : null,
        'videoRenderer' => _fromVideoRenderer(value, playlistId),
        'playlistVideoRenderer' => _fromVideoRenderer(value, playlistId),
        _ => null,
      };
    }

    void visit(dynamic node) {
      if (node is List) {
        var hasEpisodes = false;
        String? token;
        for (final e in node) {
          if (e is Map && e.length == 1) {
            final key = e.keys.first;
            final m = parse('$key', e[key]);
            if (m != null) {
              hasEpisodes = true;
              if (seen.add(m.id)) out.add(m);
              continue;
            }
            final t = _continuationToken(e);
            if (t != null) {
              token ??= t;
              continue;
            }
          }
          visit(e);
        }
        if (token != null) {
          if (hasEpisodes) sibling ??= token;
          any ??= token;
        }
      } else if (node is Map) {
        for (final entry in node.entries) {
          final m = parse('${entry.key}', entry.value);
          if (m != null) {
            if (seen.add(m.id)) out.add(m);
            continue;
          }
          visit(entry.value);
        }
      }
    }

    visit(_body(json));
    return YtEpisodePage(out, sibling ?? any);
  }

  /// "2:58:06" / "42:16" → Duration; null for anything else ("LIVE").
  static Duration? parseClock(String? text) {
    final t = text?.trim() ?? '';
    if (!_clock.hasMatch(t)) return null;
    var sec = 0;
    for (final p in t.split(':')) {
      sec = sec * 60 + int.parse(p);
    }
    return Duration(seconds: sec);
  }

  /// Only the parts of a response that hold results — the header, topbar
  /// and engagement panels carry unrelated continuation tokens.
  static List _body(Map json) => [
        json['contents'],
        json['onResponseReceivedActions'],
        json['onResponseReceivedCommands'],
        json['continuationContents'],
      ];

  /// Depth-first walk; [visit] returns true when it consumed the node.
  static void _walk(
      dynamic node, bool Function(String key, dynamic value) visit) {
    if (node is Map) {
      for (final e in node.entries) {
        if (!visit('${e.key}', e.value)) _walk(e.value, visit);
      }
    } else if (node is List) {
      for (final e in node) {
        _walk(e, visit);
      }
    }
  }

  static String? _continuationToken(Map e) {
    final vm = e['continuationItemViewModel'];
    if (vm is Map) {
      final t = vm['continuationCommand']?['innertubeCommand']
          ?['continuationCommand']?['token'];
      if (t is String && t.isNotEmpty) return t;
    }
    final r = e['continuationItemRenderer'];
    if (r is Map) {
      final ep = r['continuationEndpoint'] ??
          r['button']?['buttonRenderer']?['command'];
      final t = ep?['continuationCommand']?['token'];
      if (t is String && t.isNotEmpty) return t;
    }
    return null;
  }

  static YtPodcastShow? _show(
      Map lockup, String? fallbackAuthor, String? fallbackId) {
    final id = lockup['contentId']?.toString() ?? '';
    final md = lockup['metadata']?['lockupMetadataViewModel'];
    if (id.isEmpty || md is! Map) return null;
    final title = md['title']?['content']?.toString() ?? '';
    final image = lockup['contentImage'];
    final primary = image?['collectionThumbnailViewModel']?['primaryThumbnail']
        ?['thumbnailViewModel'];
    final sources = primary?['image']?['sources'] ??
        image?['thumbnailViewModel']?['image']?['sources'];

    final rows = _rows(md);
    final channel = _channelRun(rows);
    String? updated;
    for (final row in rows.take(2)) {
      for (final part in _parts(row)) {
        final text = part['text'];
        if (text is! Map || text['commandRuns'] != null) continue;
        final c = text['content']?.toString().trim() ?? '';
        if (c.isNotEmpty && c.length < 60) updated ??= c;
      }
    }

    return YtPodcastShow(
      playlistId: id,
      title: title,
      author: channel?.$1 ?? fallbackAuthor ?? '',
      authorId: channel?.$2 ?? fallbackId,
      thumbnailUrl: _largest(sources) ?? '',
      episodeCountText: _badges(image).firstOrNull,
      updatedText: updated,
    );
  }

  static MediaItem? _fromVideoLockup(Map lockup, String? playlistId) {
    final id = lockup['contentId']?.toString() ?? '';
    final md = lockup['metadata']?['lockupMetadataViewModel'];
    if (id.isEmpty || md is! Map) return null;
    final image = lockup['contentImage'];
    final thumbs =
        image?['thumbnailViewModel']?['image']?['sources'] as List? ?? const [];
    final length =
        _badges(image).where((b) => _clock.hasMatch(b.trim())).firstOrNull;

    final rows = _rows(md);
    final channel = _channelRun(rows);
    final author = channel?.$1 ??
        (rows.isNotEmpty
            ? _parts(rows.first).firstOrNull?['text']?['content']?.toString()
            : null);

    String? date;
    for (final row in rows.skip(1)) {
      final parts = _parts(row)
          .map((p) => p['text']?['content']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length > 1) {
        date = parts.last;
      } else if (parts.length == 1 &&
          !parts.first.toLowerCase().contains('view')) {
        date = parts.first;
      }
    }

    return _episode(
      id: id,
      title: md['title']?['content']?.toString() ?? '',
      author: author ?? '',
      authorId: channel?.$2,
      length: length,
      date: date,
      description: null,
      thumbnails: thumbs,
      playlistId: playlistId,
    );
  }

  /// Handles both `videoRenderer` and the legacy `playlistVideoRenderer`.
  static MediaItem? _fromVideoRenderer(Map v, String? playlistId) {
    final id = v['videoId']?.toString() ?? '';
    if (id.isEmpty) return null;
    final byline = (v['longBylineText'] ??
        v['ownerText'] ??
        v['shortBylineText'])?['runs'] as List?;
    final first = byline?.firstOrNull;
    var length = v['lengthText']?['simpleText']?.toString();
    if (length == null && v['lengthSeconds'] != null) {
      final s = int.tryParse('${v['lengthSeconds']}');
      if (s != null) length = _formatClock(s);
    }
    final infoRuns = v['videoInfo']?['runs'] as List?;
    return _episode(
      id: id,
      title: _text(v['title']) ?? '',
      author: first?['text']?.toString() ?? '',
      authorId: first?['navigationEndpoint']?['browseEndpoint']?['browseId']
          ?.toString(),
      length: length,
      date: v['publishedTimeText']?['simpleText']?.toString() ??
          (infoRuns != null && infoRuns.length > 1
              ? infoRuns.last['text']?.toString()
              : null),
      description: _text(v['descriptionSnippet']),
      thumbnails: v['thumbnail']?['thumbnails'] as List? ?? const [],
      playlistId: playlistId,
    );
  }

  static MediaItem _episode({
    required String id,
    required String title,
    required String author,
    required String? authorId,
    required String? length,
    required String? date,
    required String? description,
    required List thumbnails,
    required String? playlistId,
  }) {
    final duration = parseClock(length);
    final best = _largest(thumbnails);
    return MediaItemBuilder.fromJson({
      'videoId': id,
      'title': title,
      'thumbnails': [
        if (best != null) {'url': best},
      ],
      'length': duration != null ? length!.trim() : null,
      'duration': duration?.inSeconds,
      'artists': [
        {'name': author, 'id': authorId},
      ],
      'date': date,
      'description': description,
      'videoType': 'MUSIC_VIDEO_TYPE_UGC',
      'resultType': 'video',
      'url': null,
      'isPodcast': true,
      'showVideo': true,
      'podcastSource': 'yt_podcast',
      if (playlistId != null) 'podcastPlaylistId': playlistId,
    });
  }

  static List _rows(Map md) =>
      md['metadata']?['contentMetadataViewModel']?['metadataRows'] as List? ??
      const [];

  static List<Map> _parts(dynamic row) =>
      (row is Map ? row['metadataParts'] as List? : null)
          ?.whereType<Map>()
          .toList() ??
      const [];

  /// First metadata part linking to a channel: (name, UC… id).
  static (String, String)? _channelRun(List rows) {
    for (final row in rows) {
      for (final part in _parts(row)) {
        final text = part['text'];
        final runs = text is Map ? text['commandRuns'] as List? : null;
        for (final run in runs ?? const []) {
          final id = run?['onTap']?['innertubeCommand']?['browseEndpoint']
                  ?['browseId']
              ?.toString();
          if (id != null && id.startsWith('UC')) {
            return ('${text['content'] ?? ''}'.trim(), id);
          }
        }
      }
    }
    return null;
  }

  static List<String> _badges(dynamic image) {
    final out = <String>[];
    _walk(image, (key, value) {
      if (key != 'thumbnailBadgeViewModel' || value is! Map) return false;
      final t = value['text']?.toString() ?? '';
      if (t.isNotEmpty) out.add(t);
      return true;
    });
    return out;
  }

  static String? _largest(dynamic sources) {
    if (sources is! List) return null;
    String? best;
    var bestW = -1;
    for (final s in sources) {
      if (s is! Map) continue;
      final url = s['url']?.toString() ?? '';
      if (url.isEmpty) continue;
      final w = int.tryParse('${s['width'] ?? 0}') ?? 0;
      if (w >= bestW) {
        bestW = w;
        best = url;
      }
    }
    return best;
  }

  static String? _text(dynamic node) {
    if (node is! Map) return null;
    if (node['simpleText'] != null) return node['simpleText'].toString();
    final runs = node['runs'];
    if (runs is List) return runs.map((r) => r['text'] ?? '').join();
    return null;
  }

  static String _formatClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// YouTube podcasts over the InnerTube WEB client, the same requests the
/// NewPipe-based WizeStream app makes. Every method throws on failure.
class YoutubePodcastService {
  YoutubePodcastService._();

  /// Overridable so tests can target `https://youtubei.googleapis.com`.
  static String baseUrl = 'https://www.youtube.com';

  static const clientVersion = '2.20250901.00.00';
  static const _destination = 'FEpodcasts_destination';
  static const _showsParams = 'qgcCCAI=';
  static const _episodesParams = 'qgcCCAM=';
  static const _channelPodcastsParams = 'Eghwb2RjYXN0c_IGBQoDugEA';

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
    headers: {
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/137.0.0.0 Safari/537.36',
      'x-youtube-client-name': '1',
      'x-youtube-client-version': clientVersion,
    },
  ));

  static String get _hl {
    try {
      if (Hive.isBoxOpen('AppPrefs')) {
        final v = Hive.box('AppPrefs').get('contentLanguage');
        if (v is String && v.isNotEmpty) return v;
      }
    } catch (_) {}
    return 'en';
  }

  static Future<Map> _post(String endpoint, Map<String, dynamic> body) async {
    final res = await _dio.post(
      '$baseUrl/youtubei/v1/$endpoint?prettyPrint=false',
      data: {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': clientVersion,
            'hl': _hl,
            'gl': 'US',
          },
        },
        ...body,
      },
    );
    final data = res.data;
    if (data is! Map) {
      throw StateError('YouTube $endpoint: unexpected response');
    }
    return data;
  }

  static Future<List<YtPodcastShow>> popularShows() async =>
      YoutubePodcastParser.showsFrom(await _post(
          'browse', {'browseId': _destination, 'params': _showsParams}));

  static Future<List<MediaItem>> popularEpisodes() async =>
      YoutubePodcastParser.popularEpisodesFrom(await _post(
          'browse', {'browseId': _destination, 'params': _episodesParams}));

  static Future<List<YtPodcastShow>> searchShows(String query) async =>
      YoutubePodcastParser.showsFrom(await _post('search', {'query': query}));

  static Future<List<YtPodcastShow>> channelShows(String channelId) async =>
      YoutubePodcastParser.showsFrom(await _post(
          'browse', {'browseId': channelId, 'params': _channelPodcastsParams}));

  /// First page when [continuation] is null, otherwise the page it names.
  static Future<YtEpisodePage> showEpisodes(String playlistId,
      {String? continuation}) async {
    final id =
        playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;
    final json = await _post(
        'browse',
        continuation != null
            ? {'continuation': continuation}
            : {'browseId': 'VL$id'});
    return YoutubePodcastParser.episodesFrom(json, playlistId: id);
  }
}
