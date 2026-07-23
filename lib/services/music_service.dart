// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/models/thumbnail.dart';
import '/services/ban_service.dart';
import '/services/utils.dart';
import '/services/yt_auth_service.dart';
import '../utils/helper.dart';
import 'constant.dart';
import 'continuations.dart';
import 'nav_parser.dart';

enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': domain,
    'cookie': 'CONSENT=YES+1; SOCS=CAI',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
      },
      'user': {}
    }
  };

  @override
  void onInit() {
    init();
    super.onInit();
  }

  final dio = Dio();

  Future<void> init() async {
    //check visitor id in data base, if not generate one , set lang code
    final date = DateTime.now();
    _context['context']['client']['clientVersion'] =
        "1.${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}.01.00";
    final signatureTimestamp = getDatestamp() - 1;
    _context['playbackContext'] = {
      'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
    };

    final appPrefsBox = Hive.box('AppPrefs');
    hlCode = appPrefsBox.get('contentLanguage') ?? "en";
    if (appPrefsBox.containsKey('visitorId')) {
      final visitorData = appPrefsBox.get("visitorId");
      if (visitorData != null && !isExpired(epoch: visitorData['exp'])) {
        _headers['X-Goog-Visitor-Id'] = visitorData['id'];
        appPrefsBox.put("visitorId", {
          'id': visitorData['id'],
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2590200
        });
        printINFO("Got Visitor id ($visitorData['id']) from Box");
        return;
      }
    }

    final visitorId = await genrateVisitorId();
    if (visitorId != null) {
      _headers['X-Goog-Visitor-Id'] = visitorId;
      printINFO("New Visitor id generated ($visitorId)");
      appPrefsBox.put("visitorId", {
        'id': visitorId,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000
      });
      return;
    }
    // not able to generate in that case
    _headers['X-Goog-Visitor-Id'] =
        visitorId ?? "CgttN24wcmd5UzNSWSi2lvq2BjIKCgJKUBIEGgAgYQ%3D%3D";
  }

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  Future<String?> genrateVisitorId() async {
    try {
      final response =
          await dio.get(domain, options: Options(headers: _headers));
      final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
      final matches = reg.firstMatch(response.data.toString());
      String? visitorId;
      if (matches != null) {
        final ytcfg = json.decode(matches.group(1).toString());
        visitorId = ytcfg['VISITOR_DATA']?.toString();
      }
      return visitorId;
    } catch (e) {
      return null;
    }
  }

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data,
      {additionalParams = "", int retries = 2}) async {
    //print("$baseUrl$action$fixedParms$additionalParams          data:$data");
    try {
      final response =
          await dio.post("$baseUrl$action$fixedParms$additionalParams",
              options: Options(
                // Auth headers personalize the feed when a YouTube
                // account is connected; empty map when anonymous.
                headers: {..._headers, ...YtAuthService.authHeaders()},
              ),
              data: data);

      if (response.statusCode == 200) {
        return response;
      } else if (retries > 0) {
        return _sendRequest(action, data,
            additionalParams: additionalParams, retries: retries - 1);
      } else {
        throw NetworkError();
      }
    } on DioException catch (e) {
      printINFO("Error $e");
      throw NetworkError();
    }
  }

  // Future<List<Map<String, dynamic>>>
  Future<dynamic> getHome({int limit = 4}) async {
    final data = Map.from(_context);
    data["browseId"] = "FEmusic_home";
    final response = await _sendRequest("browse", data);
    final results = nav(response.data, single_column_tab + section_list);
    final home = [...parseMixedContent(results)];

    final sectionList =
        nav(response.data, single_column_tab + ['sectionListRenderer']);
    //inspect(sectionList);
    //print(sectionList.containsKey('continuations'));
    if (sectionList.containsKey('continuations')) {
      requestFunc(additionalParams) async {
        return (await _sendRequest("browse", data,
                additionalParams: additionalParams))
            .data;
      }

      parseFunc(contents) => parseMixedContent(contents);
      final x = (await getContinuations(sectionList, 'sectionListContinuation',
          limit - home.length, requestFunc, parseFunc));
      // inspect(x);
      home.addAll([...x]);
    }

    return home;
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory,
      {String? countryCode}) async {
    final List<Map<String, dynamic>> charts = [];
    final data = Map.from(_context);

    data['browseId'] = 'FEmusic_charts';
    data['context']['client']["hl"] = 'en';
    if (countryCode != null) {
      data['formData'] = {
        'selectedValues': [countryCode]
      };
    }
    final response = (await _sendRequest('browse', data)).data;
    final results = nav(response, single_column_tab + section_list);
    results.removeAt(0);
    for (dynamic result in results) {
      if (nav(result, [
            "musicCarouselShelfRenderer",
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            ...title_text
          ]) ==
          "Video charts") {
        for (dynamic item in result['musicCarouselShelfRenderer']['contents']) {
          final chartItem =
              await getChartItems(parseChartsItemBrowseId(item), catogory);
          charts.add(chartItem);
        }
      } else {
        continue;
      }
    }

    return charts;
  }

  Future<Map<String, dynamic>> getChartItems(
      Map<String, dynamic> item, String catogory) async {
    final catString = catogory == "TMV" ? "Top Music Videos" : "Trending";
    if ((item['title'])!.contains(catString)) {
      final songs = (await getPlaylistOrAlbumSongs(
          playlistId: item['browseId']))['tracks'];
      final limitedSongs = songs.length > 24 ? songs.sublist(0, 24) : songs;
      return {'title': item['title'], 'contents': limitedSongs};
    }
    return {'title': item['title'], 'contents': []};
  }

  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    if (videoId.isNotEmpty && videoId.substring(0, 4) == "MPED") {
      videoId = videoId.substring(4);
    }
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    if (videoId == "" && playlistId == null) {
      throw Exception(
          "You must provide either a video id, a playlist id, or both");
    }
    if (videoId != "") {
      data['videoId'] = videoId;
      playlistId ??= "RDAMVM$videoId";

      if (!(radio || shuffle)) {
        data['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': "MUSIC_VIDEO_TYPE_ATV",
          }
        };
      }
    }

    playlistId = validatePlaylistId(playlistId!);
    data['playlistId'] = playlistId;
    final isPlaylist =
        playlistId.startsWith('PL') || playlistId.startsWith('OLA');
    if (shuffle) {
      data['params'] = "wAEB8gECKAE%3D";
    }
    if (radio) {
      data['params'] = "wAEB";
    }

    final List<dynamic> tracks = [];
    dynamic lyricsBrowseId, relatedBrowseId, playlist;
    final results = {};

    if (additionalParamsNext == null) {
      final response = (await _sendRequest("next", data)).data;
      final watchNextRenderer = nav(response, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer'
      ]);

      if (watchNextRenderer is! Map) {
        if (onlyRelated) {
          return {
            'lyrics': null,
            'related': null,
          };
        }
        return {
          'tracks': <dynamic>[],
          'playlistId': playlistId,
          'lyrics': null,
          'related': null,
          'additionalParamsForNext': null,
        };
      }

      lyricsBrowseId = getTabBrowseId(
          Map<String, dynamic>.from(watchNextRenderer), 1);
      relatedBrowseId = getTabBrowseId(
          Map<String, dynamic>.from(watchNextRenderer), 2);
      if (onlyRelated) {
        return {
          'lyrics': lyricsBrowseId,
          'related': relatedBrowseId,
        };
      }

      final panel = nav(watchNextRenderer, [
        ...tab_content,
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer'
      ]);
      if (panel is Map) {
        results.addAll(Map<String, dynamic>.from(panel));
      }
      if (results['contents'] is List) {
        final playlistIds = results['contents']
            .map((content) => nav(content,
                ['playlistPanelVideoRenderer', ...navigation_playlist_id]))
            .where((e) => e != null)
            .toList();
        if (playlistIds.isNotEmpty) {
          playlist = playlistIds.first;
        }
        tracks.addAll(parseWatchPlaylist(results['contents']));
      }
    }

    dynamic additionalParamsForNext;
    if (results.containsKey('continuations') || additionalParamsNext != null) {
      requestFunc(additionalParams) async =>
          (await _sendRequest("next", data, additionalParams: additionalParams))
              .data;
      parseFunc(contents) => parseWatchPlaylist(contents);
      final x = await getContinuations(results, 'playlistPanelContinuation',
          limit - tracks.length, requestFunc, parseFunc,
          ctokenPath: isPlaylist ? '' : 'Radio',
          isAdditionparamReturnReq: true,
          additionalParams_: additionalParamsNext);
      additionalParamsForNext = x[1];
      tracks.addAll(List<dynamic>.from(x[0]));
    }

    return {
      // "Never Play This": banned songs never enter radio / up-next,
      // but an explicitly requested seed song is kept.
      'tracks': BanService.filterTracks(tracks, keepVideoId: videoId),
      'playlistId': playlist,
      'lyrics': lyricsBrowseId,
      'related': relatedBrowseId,
      'additionalParamsForNext': additionalParamsForNext
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final response = await dio.get("${domain}playlist",
        options: Options(headers: _headers),
        queryParameters: {"list": audioPlaylistId});
    final reg = RegExp(r'\"MPRE.+?\"');
    final matchs = reg.firstMatch(response.data.toString());
    if (matchs != null) {
      final x = (matchs[0])!;
      final res = (x.substring(1)).split("\\")[0];
      return res;
    }
    return audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final params = await getWatchPlaylist(videoId: videoId, onlyRelated: true);
    final relatedId = params['related'];
    // Videos / some seeds have no Related tab — browsing null hangs or 400s.
    if (relatedId is! String || relatedId.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final data = Map.from(_context);
    data['browseId'] = relatedId;
    data['context']['client']['hl'] = hlCode;
    final response = (await _sendRequest('browse', data)).data;
    final sections = nav(response, ['contents'] + section_list);
    if (sections is! List) return <Map<String, dynamic>>[];
    return parseMixedContent(sections);
  }

  dynamic getLyrics(String browseId) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final response = (await _sendRequest('browse', data)).data;
    return nav(
      response,
      ['contents', ...section_list_item, ...description_shelf, ...description],
    );
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int limit = 3000,
      bool related = false,
      int suggestionsLimit = 0}) async {
    // Podcast browse IDs start with MPSP — use dedicated podcast parser.
    // YouTube channel-as-podcast subscriptions use UC… channel ids.
    if (playlistId != null &&
        (playlistId.startsWith('MPSP') || playlistId.startsWith('MPED'))) {
      return getPodcast(playlistId, limit: limit);
    }
    if (playlistId != null &&
        RegExp(r'^UC[\w-]{20,}$').hasMatch(playlistId)) {
      return getChannelAsPodcast(playlistId, limit: limit);
    }
    String browseId = playlistId != null
        ? (playlistId.startsWith("VL") ? playlistId : "VL$playlistId")
        : albumId!;
    if (albumId != null && albumId.contains("OLAK5uy")) {
      browseId = await getAlbumBrowseId(browseId);
    }
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response =
        (await _sendRequest('browse', data)).data;
    if (playlistId != null) {
      final Map<String, dynamic> header =
          nav(response, ['header', "musicDetailHeaderRenderer"]) ??
              nav(response, [
                'contents',
                "twoColumnBrowseResultsRenderer",
                'tabs',
                0,
                "tabRenderer",
                "content",
                "sectionListRenderer",
                "contents",
                0,
                "musicResponsiveHeaderRenderer"
              ]);

      final Map<String, dynamic> results =
          nav(response, musicPlaylistShelfRenderer) ??
              nav(
                response,
                [
                  'contents',
                  "singleColumnBrowseResultsRenderer",
                  "tabs",
                  0,
                  "tabRenderer",
                  "content",
                  'sectionListRenderer',
                  'contents',
                  0,
                  "musicPlaylistShelfRenderer"
                ],
              );
      final Map<String, dynamic> playlist = {'id': results['playlistId']};

      playlist['title'] = nav(header, title_text);
      playlist['thumbnails'] = nav(header, thumnail_cropped) ??
          nav(header, [
            "thumbnail",
            "musicThumbnailRenderer",
            "thumbnail",
            "thumbnails"
          ]);
      playlist["description"] = nav(header, description);
      final int runCount = header['subtitle']['runs'].length;
      if (runCount > 1) {
        playlist['author'] = {
          'name': nav(header, subtitle2),
          'id': nav(header, ['subtitle', 'runs', 2] + navigation_browse_id)
        };
        if (runCount == 5) {
          playlist['year'] = nav(header, subtitle3);
        }
      }

      final int secondSubtitleRunCount =
          header['secondSubtitle']['runs'].length;
      final String count = (((header['secondSubtitle']['runs']
                      [secondSubtitleRunCount % 3]['text'])
                  .split(' ')[0])
              .split(',') as List)
          .join();
      final int songCount = int.parse(count);
      if (header['secondSubtitle']['runs'].length > 1) {
        playlist['duration'] = header['secondSubtitle']['runs']
            [(secondSubtitleRunCount % 3) + 2]['text'];
      }
      playlist['trackCount'] = songCount;

      // requestFunc(additionalParams) async => (await _sendRequest("browse", data,
      //         additionalParams: additionalParams))
      //     .data;

      requestFuncCountinuation(cont) async =>
          (await _sendRequest("browse", {...data, ...cont})).data;

      if (songCount > 0) {
        // Pass playlist cover as fallback when YTM omits per-track thumbnails
        // (otherwise song rows show the generic icon instead of art).
        final coverThumbs = playlist['thumbnails'];
        playlist['tracks'] =
            parsePlaylistItems(results['contents'], thumbnailsM: coverThumbs);
        limit = songCount;

        List<dynamic> parseFunc(contents) =>
            parsePlaylistItems(contents, thumbnailsM: coverThumbs);

        playlist['tracks'] = [
          ...(playlist['tracks']),
          ...(await getContinuationsPlaylist(
              results, limit, requestFuncCountinuation, parseFunc))
        ];
      }
      playlist['duration_seconds'] = sumTotalDuration(playlist);
      return playlist;
    }

    //album content
    final album = parseAlbumHeader(response);
    dynamic results = nav(
          response,
          [
            'contents',
            "twoColumnBrowseResultsRenderer",
            "secondaryContents",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        ) ??
        nav(
          response,
          [
            'contents',
            "singleColumnBrowseResultsRenderer",
            "tabs",
            0,
            "tabRenderer",
            "content",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        );

    album['tracks'] = parsePlaylistItems(results['contents'],
        artistsM: album['artists'],
        thumbnailsM: album["thumbnails"],
        albumIdName: {"id": albumId, 'name': album['title']},
        albumYear: album['year'],
        isAlbum: true);
    results = nav(
      response,
      [...single_column_tab, ...section_list, 1, 'musicCarouselShelfRenderer'],
    );
    if (results != null) {
      List contents = [];
      if (results.runtimeType.toString().contains("Iterable") ||
          results.runtimeType.toString().contains("List")) {
        for (dynamic result in results) {
          contents.add(parseAlbum(result['musicTwoRowItemRenderer']));
        }
      } else {
        contents
            .add(parseAlbum(results['contents'][0]['musicTwoRowItemRenderer']));
      }
      album['other_versions'] = contents;
    }
    album['duration_seconds'] = sumTotalDuration(album);

    return album;
  }

  /// Fetch a podcast and its episodes (YouTube Music podcasts).
  /// [playlistId] may be `PLxxx`, `MPSPPLxxx`, or a full browse id.
  Future<Map<String, dynamic>> getPodcast(String playlistId,
      {int limit = 100}) async {
    final browseId =
        playlistId.startsWith('MPSP') ? playlistId : 'MPSP$playlistId';
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response =
        (await _sendRequest('browse', data)).data;

    final twoColumns = nav(response, [
      'contents',
      'twoColumnBrowseResultsRenderer',
    ]);
    final header = twoColumns == null
        ? null
        : (nav(twoColumns, [
              ...tab_content,
              ...section_list_item,
              'musicResponsiveHeaderRenderer',
            ]) ??
            nav(twoColumns, [
              ...tab_content,
              ...section_list_item,
              'musicDetailHeaderRenderer',
            ]));

    final results = twoColumns == null
        ? null
        : (nav(twoColumns, [
              'secondaryContents',
              ...section_list_item,
              'musicShelfRenderer',
            ]) ??
            nav(twoColumns, [
              'secondaryContents',
              ...section_list_item,
              'musicPlaylistShelfRenderer',
            ]));

    final podcast = <String, dynamic>{
      'playlistId': browseId,
      'title': nav(header, title_text) ?? '',
      'description': nav(header, [
            'description',
            'musicDescriptionShelfRenderer',
            ...description,
          ]) ??
          nav(header, description) ??
          'Podcast',
      'thumbnails': nav(header, [
            'thumbnail',
            'musicThumbnailRenderer',
            'thumbnail',
            'thumbnails',
          ]) ??
          nav(header, thumnail_cropped) ??
          [
            {'url': Playlist.thumbPlaceholderUrl}
          ],
      'isCloudPlaylist': true,
      'kind': 'podcast',
    };

    final strapline = nav(header, ['straplineTextOne', 'runs', 0]);
    if (strapline != null) {
      podcast['author'] = {
        'name': strapline['text'],
        'id': nav(strapline, navigation_browse_id),
      };
    }

    List tracks = [];
    if (results != null && results['contents'] != null) {
      final coverThumbs = podcast['thumbnails'];
      tracks = parsePodcastEpisodes(results['contents'],
          fallbackThumbs: coverThumbs);
      if (results.containsKey('continuations')) {
        requestFunc(additionalParams) async =>
            (await _sendRequest('browse', data,
                    additionalParams: additionalParams))
                .data;
        parseFunc(contents) =>
            parsePodcastEpisodes(contents, fallbackThumbs: coverThumbs);
        final remaining = limit - tracks.length;
        if (remaining > 0) {
          try {
            final cont = await getContinuations(
              results,
              'musicShelfContinuation',
              remaining,
              requestFunc,
              parseFunc,
            );
            tracks = [...tracks, ...cont];
          } catch (_) {
            // Continuations optional for podcasts
          }
        }
      }
    }
    podcast['tracks'] = tracks;
    podcast['trackCount'] = tracks.length;
    return podcast;
  }

  /// Subscribe-to-YouTube-channel-as-podcast (Podcini-style): channel uploads
  /// become episodes. Each episode is a real YouTube video id so the player
  /// can optionally show a 16:9 video surface.
  Future<Map<String, dynamic>> getChannelAsPodcast(String channelId,
      {int limit = 60}) async {
    final artist = await getArtist(channelId);
    final name = '${artist['name'] ?? ''}'.trim();
    final videosShelf = artist['Videos'];
    var tracks = <MediaItem>[];

    if (videosShelf is Map) {
      final content = videosShelf['content'];
      if (content is List && content.isNotEmpty) {
        tracks = _tagYtChannelEpisodes(content, name);
      }
      final endpoint = Map<String, dynamic>.from(videosShelf)..remove('content');
      if (endpoint.isNotEmpty && tracks.length < limit) {
        try {
          final more = await getArtistRealtedContent(endpoint, 'Videos');
          final results = more['results'];
          if (results is List && results.isNotEmpty) {
            tracks = _mergeMediaById(
              tracks,
              _tagYtChannelEpisodes(results, name),
            );
          }
        } catch (e) {
          printERROR('getChannelAsPodcast videos tab failed: $e');
        }
      }
    }

    if (tracks.length > limit) {
      tracks = tracks.take(limit).toList();
    }

    final thumbs = artist['thumbnails'] ??
        [
          {'url': Playlist.thumbPlaceholderUrl}
        ];
    return {
      'playlistId': channelId,
      'title': name.isNotEmpty ? name : channelId,
      'description': artist['description'] ?? 'YouTube channel',
      'thumbnails': thumbs,
      'author': {
        'name': name,
        'id': channelId,
      },
      'isCloudPlaylist': true,
      'kind': 'yt_channel',
      'tracks': tracks,
      'trackCount': tracks.length,
    };
  }

  List<MediaItem> _tagYtChannelEpisodes(List raw, String channelName) {
    final out = <MediaItem>[];
    for (final item in raw) {
      MediaItem? m;
      if (item is MediaItem) {
        m = item;
      } else if (item is Map) {
        try {
          m = MediaItemBuilder.fromJson(item);
        } catch (_) {
          m = null;
        }
      }
      if (m == null || m.id.isEmpty || m.id.startsWith('podcast_')) continue;
      out.add(m.copyWith(
        artist: (m.artist == null || m.artist!.trim().isEmpty)
            ? channelName
            : m.artist,
        extras: {
          ...?m.extras,
          'isPodcast': true,
          'showVideo': true,
          'podcastSource': 'yt_channel',
          'videoType': m.extras?['videoType'] ?? 'MUSIC_VIDEO_TYPE_UGC',
          'resultType': m.extras?['resultType'] ?? 'video',
        },
      ));
    }
    return out;
  }

  List<MediaItem> _mergeMediaById(List<MediaItem> a, List<MediaItem> b) {
    final seen = <String>{for (final e in a) e.id};
    final out = List<MediaItem>.from(a);
    for (final e in b) {
      if (seen.add(e.id)) out.add(e);
    }
    return out;
  }

  /// Discovery feed for the Podcasts tab: popular episodes + featured podcasts.
  Future<Map<String, dynamic>> getPodcastDiscovery() async {
    final result = <String, dynamic>{
      'topEpisodes': <MediaItem>[],
      'featuredPodcasts': <Playlist>[],
    };

    // Explore → popular / top podcast episodes
    try {
      final data = Map.from(_context);
      data['browseId'] = 'FEmusic_explore';
      final response = (await _sendRequest('browse', data)).data;
      final sections = nav(response, single_column_tab + section_list) ?? [];
      for (final section in sections) {
        final carousel = section['musicCarouselShelfRenderer'];
        if (carousel == null) continue;
        final contents = carousel['contents'] as List? ?? [];
        if (contents.isEmpty) continue;

        // Prefer shelf that contains podcast episodes
        final first = contents.first;
        final renderer = first['musicResponsiveListItemRenderer'] ??
            first['musicTwoRowItemRenderer'];
        if (renderer == null) continue;

        final videoType = nav(renderer, [
              ...play_button,
              'playNavigationEndpoint',
              ...navigation_video_type,
            ]) ??
            nav(first, [
              'musicResponsiveListItemRenderer',
              'onTap',
              ...navigation_video_type,
            ]);

        final isEpisodeShelf =
            videoType == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE' ||
                (nav(renderer, [
                          ...play_button,
                          'playNavigationEndpoint',
                          'watchEndpoint',
                          'videoId',
                        ]) !=
                        null &&
                    nav(renderer, navigation_browse_id)
                            ?.toString()
                            .startsWith('MP') ==
                        true);

        // Also match by title keywords when video type missing
        final shelfTitle =
            (nav(carousel, carousel_title + ['text']) ?? '').toString();
        final titleLooksLikeEpisodes =
            shelfTitle.toLowerCase().contains('episode') ||
                shelfTitle.toLowerCase().contains('podcast');

        if (!isEpisodeShelf && !titleLooksLikeEpisodes) continue;

        final episodes = <MediaItem>[];
        for (final item in contents) {
          final parsed = parseExploreEpisode(item);
          if (parsed != null) episodes.add(parsed);
        }
        if (episodes.isNotEmpty) {
          result['topEpisodes'] = episodes;
          break;
        }
      }
    } catch (e) {
      printERROR('getPodcastDiscovery explore failed: $e');
    }

    // Featured podcasts via search
    try {
      final searchRes = await search('podcast', filter: 'podcasts', limit: 20);
      final list = <Playlist>[];
      for (final entry in searchRes.entries) {
        if (entry.key == 'params' || entry.key == 'searchEndpoint') continue;
        final val = entry.value;
        if (val is! List) continue;
        for (final item in val) {
          if (item is Playlist) {
            list.add(item.copyWith(kind: 'podcast'));
          }
        }
      }
      result['featuredPodcasts'] = list;
    } catch (e) {
      printERROR('getPodcastDiscovery search failed: $e');
    }

    return result;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final data = Map.from(_context);
    data['input'] = queryStr;
    final res = nav(
            (await _sendRequest("music/get_search_suggestions", data)).data,
            ['contents', 0, 'searchSuggestionsSectionRenderer', 'contents']) ??
        [];
    return res
        .map<String?>((item) {
          return (nav(item, [
            'searchSuggestionRenderer',
            'navigationEndpoint',
            'searchEndpoint',
            'query'
          ])).toString();
        })
        .whereType<String>()
        .toList();
  }

  ///Specially created for deep-links
  Future<List> getSongWithId(String songId) async {
    final data = Map.of(_context);
    data['videoId'] = songId;
    final response = (await _sendRequest("player", data)).data;
    final category =
        nav(response, ["microformat", "microformatDataRenderer", "category"]);
    if (category == "Music" ||
        (response["videoDetails"]).containsKey("musicVideoType")) {
      final list = await getWatchPlaylist(videoId: songId);
      return [true, list['tracks']];
    }
    return [false, null];
  }

  /// Finds the square cover for a music-video track. YouTube only serves a
  /// 16:9 frame for a video, but the same song's audio-track (ATV) version has
  /// a square cover; a song-filtered search surfaces it. Returns the first
  /// non-video-frame (square) art URL, or null. Used by [CoverResolver].
  Future<String?> squareCoverForVideo(String videoId,
      {String? title, String? artist}) async {
    final query = [title, artist]
        .where((e) => e != null && e.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (query.isEmpty) return null;
    try {
      final res = await search(query, filter: 'songs', limit: 3);
      for (final value in res.values) {
        if (value is! List) continue;
        for (final item in value) {
          if (item is MediaItem) {
            final art = item.artUri?.toString() ?? '';
            if (art.isNotEmpty && !Thumbnail.isVideoFrameUrl(art)) {
              return art;
            }
          }
        }
      }
    } catch (e) {
      printERROR("squareCoverForVideo failed: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    final data = Map.of(_context);
    data['context']['client']["hl"] = 'en';
    data['query'] = query;

    final Map<String, dynamic> searchResults = {};
    final filters = [
      'albums',
      'artists',
      'playlists',
      'community_playlists',
      'featured_playlists',
      'songs',
      'videos',
      'podcasts',
      'episodes',
    ];

    if (filter != null && !filters.contains(filter)) {
      throw Exception(
          'Invalid filter provided. Please use one of the following filters or leave out the parameter: ${filters.join(', ')}');
    }

    final scopes = ['library', 'uploads'];

    if (scope != null && !scopes.contains(scope)) {
      throw Exception(
          'Invalid scope provided. Please use one of the following scopes or leave out the parameter: ${scopes.join(', ')}');
    }

    if (scope == scopes[1] && filter != null) {
      throw Exception(
          'No filter can be set when searching uploads. Please unset the filter parameter when scope is set to uploads.');
    }

    final params = getSearchParams(filter, scope, ignoreSpelling);

    if (filterParams != null || params != null) {
      data['params'] = filterParams ?? params;
    }

    final response = (await _sendRequest("search", data)).data;

    if (response['contents'] == null) {
      return searchResults;
    }

    dynamic results;

    if ((response['contents']).containsKey('tabbedSearchResultsRenderer')) {
      final tabIndex =
          scope == null || filter != null ? 0 : scopes.indexOf(scope) + 1;
      results = response['contents']['tabbedSearchResultsRenderer']['tabs']
          [tabIndex]['tabRenderer']['content'];
    } else {
      results = response['contents'];
    }

    // Search Chips
    /*
    {
      "searchEndpoint": {
        "Songs": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Videos": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Albums": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Artists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Community playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Featured playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB"
      }
     */
    if (filter == null) {
      final searchChips = nav(results,
          ['sectionListRenderer', 'header', "chipCloudRenderer", "chips"]);

      searchResults['searchEndpoint'] = {};
      if (searchChips != null) {
        for (dynamic chipsItemRenderer in searchChips) {
          final chip = chipsItemRenderer['chipCloudChipRenderer'];
          final chipText = nav(chip, ['text', 'runs', 0, 'text']);
          if (chipText == null) continue;
          final normalized = _normalizeSearchCategory('$chipText');
          searchResults['searchEndpoint'][normalized] =
              nav(chip, ['navigationEndpoint', 'searchEndpoint', 'params']);
          // Keep raw label too when YTM uses a different spelling.
          if (normalized != chipText) {
            searchResults['searchEndpoint'][chipText] =
                searchResults['searchEndpoint'][normalized];
          }
        }
      }

      // Always expose filter tabs from chips (RiPlay-style), even when the
      // unfiltered top shelves omit that category.
      const seedTabs = [
        'Songs',
        'Videos',
        'Albums',
        'Artists',
        'Community playlists',
        'Featured playlists',
        'Podcasts',
        'Episodes',
      ];
      final endpoints = searchResults['searchEndpoint'] as Map;
      for (final key in seedTabs) {
        if (endpoints.containsKey(key) && !searchResults.containsKey(key)) {
          searchResults[key] = [];
        }
      }
    }

    /// End Search Chips

    results = nav(results, ['sectionListRenderer', 'contents']);
    if (results == null) {
      return searchResults;
    }

    // Flatten itemSectionRenderer wrappers (some payloads nest shelves).
    final List<dynamic> flatResults = [];
    for (final res in results) {
      if (res is Map && res['itemSectionRenderer'] != null) {
        final sectionContents = res['itemSectionRenderer']['contents'];
        if (sectionContents is List) {
          flatResults.addAll(sectionContents);
        }
      } else {
        flatResults.add(res);
      }
    }
    results = flatResults;

    if (results.isEmpty) {
      return searchResults;
    }

    String? type;

    for (var res in results) {
      if (res is! Map) continue;
      String category;
      if (res['musicShelfRenderer'] != null) {
        dynamic itemResults = res['musicShelfRenderer']['contents'];
        String? typeFilter = filter;
        category = "mixed";
        final resultTypes = [
          'artist',
          'playlist',
          'song',
          'video',
          'station',
          'podcast',
          'episode',
        ];
        // Derive singular type from filter before parsing (podcasts → podcast)
        type = typeFilter?.substring(0, typeFilter.length - 1).toLowerCase();

        if (filter == null) {
          final shelfTitle =
              nav(res, ['musicShelfRenderer', ...title_text])?.toString();
          category = _normalizeSearchCategory(shelfTitle);
          final mixedItems =
              parseSearchResults(itemResults, resultTypes, type, category);
          if (!searchResults.containsKey(category)) {
            searchResults[category] = <dynamic>[];
          }
          final bucket = searchResults[category] as List;
          for (final item in mixedItems) {
            if (item == null) continue;
            // Prefer shelf title; fall back to runtime type if shelf was generic.
            final key = category == 'mixed' || category.isEmpty
                ? _categoryForSearchItem(item)
                : category;
            if (key != category) {
              if (!searchResults.containsKey(key)) {
                searchResults[key] = <dynamic>[];
              }
              final alt = searchResults[key] as List;
              if (alt.length < 3) alt.add(item);
            } else if (bucket.length < 3) {
              bucket.add(item);
            }
          }
        } else {
          category = _normalizeSearchCategory(
              nav(res, ['musicShelfRenderer', ...title_text])?.toString());
          // Prefer the requested filter label so tabs can find results.
          final tabCategory = _categoryFromFilter(filter) ?? category;
          searchResults[tabCategory] = parseSearchResults(
              res['musicShelfRenderer']['contents'],
              resultTypes,
              type,
              tabCategory);
          category = tabCategory;
        }
      } else {
        continue;
      }

      if (filter != null) {
        requestFunc(additionalParams) async =>
            (await _sendRequest("search", data,
                    additionalParams: additionalParams))
                .data;
        parseFunc(contents) => parseSearchResults(
            contents,
            [
              'artist',
              'playlist',
              'song',
              'video',
              'station',
              'podcast',
              'episode',
            ],
            type,
            category);

        if (searchResults.containsKey(category)) {
          final x = await getContinuations(
              res['musicShelfRenderer'],
              'musicShelfContinuation',
              limit - ((searchResults[category] as List).length),
              requestFunc,
              parseFunc,
              isAdditionparamReturnReq: true);

          searchResults["params"] = {
            'data': data,
            "type": type,
            "category": category,
            'additionalParams': x[1],
          };

          searchResults[category] = [
            ...(searchResults[category] as List),
            ...(x[0])
          ];
        }
      }
    }

    return searchResults;
  }

  /// Map YTM shelf / chip labels onto stable English tab keys.
  static String _normalizeSearchCategory(String? raw) {
    return normalizeSearchCategory(raw);
  }

  /// Public for tests / debugging.
  static String normalizeSearchCategory(String? raw) {
    final c = (raw ?? '').trim();
    if (c.isEmpty) return 'Songs';
    final lower = c.toLowerCase();
    if (lower.contains('community') && lower.contains('playlist')) {
      return 'Community playlists';
    }
    if (lower.contains('featured') && lower.contains('playlist')) {
      return 'Featured playlists';
    }
    if (lower.contains('playlist')) return 'Community playlists';
    if (lower.contains('song')) return 'Songs';
    if (lower.contains('video')) return 'Videos';
    if (lower.contains('album')) return 'Albums';
    if (lower.contains('artist')) return 'Artists';
    if (lower.contains('podcast')) return 'Podcasts';
    if (lower.contains('episode')) return 'Episodes';
    // Already a known English key
    const known = {
      'Songs',
      'Videos',
      'Albums',
      'Artists',
      'Community playlists',
      'Featured playlists',
      'Podcasts',
      'Episodes',
      'Playlists',
    };
    if (known.contains(c)) return c;
    return c;
  }

  static String? _categoryFromFilter(String filter) {
    switch (filter) {
      case 'songs':
        return 'Songs';
      case 'videos':
        return 'Videos';
      case 'albums':
        return 'Albums';
      case 'artists':
        return 'Artists';
      case 'community_playlists':
        return 'Community playlists';
      case 'featured_playlists':
        return 'Featured playlists';
      case 'playlists':
        return 'Community playlists';
      case 'podcasts':
        return 'Podcasts';
      case 'episodes':
        return 'Episodes';
      default:
        return null;
    }
  }

  static String _categoryForSearchItem(dynamic item) {
    if (item is MediaItem) {
      final vt = '${item.extras?['videoType'] ?? ''}';
      if (vt.contains('PODCAST')) return 'Episodes';
      if (vt == 'MUSIC_VIDEO_TYPE_ATV' || vt.isEmpty) return 'Songs';
      return 'Videos';
    }
    if (item is Album) return 'Albums';
    if (item is Artist) return 'Artists';
    if (item is Playlist) {
      if (item.kind == 'podcast') return 'Podcasts';
      return 'Community playlists';
    }
    final name = item.runtimeType.toString();
    if (name == 'Album') return 'Albums';
    if (name == 'Artist') return 'Artists';
    if (name == 'Playlist') return 'Community playlists';
    return 'Songs';
  }

  Future<Map<String, dynamic>> getSearchContinuation(Map additionalParamsNext,
      {int limit = 10}) async {
    final data = additionalParamsNext['data'];
    final type = additionalParamsNext['type'];
    final category = additionalParamsNext['category'];
    final Map<String, dynamic> searchResults = {};

    requestFunc(additionalParams) async =>
        (await _sendRequest("search", data, additionalParams: additionalParams))
            .data;

    parseFunc(contents) => parseSearchResults(contents,
        ['artist', 'playlist', 'song', 'video', 'station'], type, category);

    final x = await getContinuations(
        {}, 'musicShelfContinuation', limit, requestFunc, parseFunc,
        isAdditionparamReturnReq: true,
        additionalParams_: additionalParamsNext['additionalParams']);

    searchResults["params"] = {
      "data": data,
      "type": type,
      "category": category,
      'additionalParams': x[1],
    };

    searchResults[category] = x[0];

    return searchResults;
  }

  Future<Map<String, dynamic>> getArtist(String channelId) async {
    if (channelId.startsWith("MPLA")) {
      channelId = channelId.substring(4);
    }
    final data = Map.from(_context);
    data['context']['client']["hl"] = 'en';
    data['browseId'] = channelId;
    final response = (await _sendRequest("browse", data)).data;
    final results = nav(response, [...single_column_tab, ...section_list]);

    final Map<String, dynamic> artist = {'description': null, 'views': null};
    final Map<String, dynamic> header = (response['header']
            ['musicImmersiveHeaderRenderer']) ??
        response['header']['musicVisualHeaderRenderer'];
    artist['name'] = nav(header, title_text);
    final descriptionShelf =
        findObjectByKey(results, description_shelf[0], isKey: true);
    if (descriptionShelf != null) {
      artist['description'] = nav(descriptionShelf, description);
      artist['views'] = descriptionShelf['subheader'] == null
          ? null
          : descriptionShelf['subheader']['runs'][0]['text'];
    }
    final dynamic subscriptionButton = header['subscriptionButton'] != null
        ? header['subscriptionButton']['subscribeButtonRenderer']
        : null;
    artist['channelId'] = channelId;
    artist['shuffleId'] = nav(header,
        ['playButton', 'buttonRenderer', ...navigation_watch_playlist_id]);
    artist['radioId'] = nav(
      header,
      ['startRadioButton', 'buttonRenderer'] + navigation_playlist_id,
    );
    artist['subscribers'] = subscriptionButton != null
        ? nav(
            subscriptionButton,
            ['subscriberCountText', 'runs', 0, 'text'],
          )
        : null;

    artist['thumbnails'] = nav(header, thumbnails);

    artist.addAll(parseArtistContents(results));
    return artist;
  }

  Future<Map<String, dynamic>> getArtistRealtedContent(
      Map<String, dynamic> browseEndpoint, String category,
      {String additionalParams = ""}) async {
    final Map<String, dynamic> result = {
      "results": [],
    };
    final data = Map.of(_context);
    browseEndpoint.remove("content");
    if (browseEndpoint.isEmpty) return result;
    data.addAll(browseEndpoint);
    final response =
        (await _sendRequest("browse", data, additionalParams: additionalParams))
            .data;
    final contents = nav(response, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
      0,
    ]);

    if (category == "Songs" || category == "Videos") {
      if (additionalParams != "") {
        final contentList = nav(response, [
          "onResponseReceivedActions",
          0,
          "appendContinuationItemsAction",
          "continuationItems"
        ]);
        final x = parsePlaylistItems(contentList);
        result['results'] = x;
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else if (contents.containsKey("gridRenderer")) {
        result['results'] = (contents['gridRenderer']['items'])
            .map((video) => parseVideo(video['musicTwoRowItemRenderer']))
            .toList();
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else {
        final collapseContent =
            nav(contents, ['musicPlaylistShelfRenderer', "collapsedItemCount"]);
        if (collapseContent != null) {
          final contentlist =
              contents['musicPlaylistShelfRenderer']['contents'];
          if (contentlist.length.toString() != collapseContent.toString()) {
            final continuationItem = contentlist.removeAt(100);
            result['results'] = parsePlaylistItems(contentlist);
            final continuationKey = nav(continuationItem, [
              "continuationItemRenderer",
              "continuationEndpoint",
              "continuationCommand",
              "token"
            ]);
            result['additionalParams'] =
                "&ctoken=$continuationKey&continuation=$continuationKey";
          } else {
            result['results'] = parsePlaylistItems(contentlist);
            result['additionalParams'] = "&ctoken=null&continuation=null";
          }
        }
        return result;
      }
    } else if (category == 'Albums' || category == 'Singles') {
      List contentlist;

      /// in continuation
      if (additionalParams != "") {
        contentlist =
            response['continuationContents']['gridContinuation']['items'];
        final continuationKey = nav(response, [
          'continuationContents',
          'gridContinuation',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      } else {
        /// in first request
        contentlist = contents['gridRenderer']['items'];

        final continuationKey = nav(contents, [
          'gridRenderer',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      }

      result['results'] = category == 'Albums'
          ? contentlist
              .map((item) => parseAlbum(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList()
          : contentlist
              .map((item) => parseSingle(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList();
    }
    return result;
  }

  Future<String?> getSongYear(String songId) async {
    final data = Map.from(_context);
    data['browseId'] = "MPTC$songId";
    try {
      final response = (await _sendRequest('browse', data)).data;
      String? year = nav(response, [
        "onResponseReceivedActions",
        0,
        "openPopupAction",
        "popup",
        "dismissableDialogRenderer",
        "metadata",
        "musicMultiRowListItemRenderer",
        "secondTitle",
        "runs",
        2,
        "text"
      ]);
      return year;
    } catch (e) {
      rethrow;
    }
  }

  @override
  void onClose() {
    dio.close();
    super.onClose();
  }
}

class NetworkError extends Error {
  final message = "Network Error !";
}
