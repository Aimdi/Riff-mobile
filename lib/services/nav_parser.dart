//navigations
// ignore_for_file: constant_identifier_names, empty_catches

import 'package:audio_service/audio_service.dart';

import '/models/media_Item_builder.dart';
import '/models/thumbnail.dart';
import '/services/utils.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';

const single_column = ['contents', 'singleColumnBrowseResultsRenderer'];
const tab_content = ['tabs', 0, 'tabRenderer', 'content'];
const List<dynamic> single_column_tab = [
  'contents',
  'singleColumnBrowseResultsRenderer',
  'tabs',
  0,
  'tabRenderer',
  'content'
];
const section_list = ['sectionListRenderer', 'contents'];
const description_shelf = ['musicDescriptionShelfRenderer'];
const run_text = ['runs', 0, 'text'];
const description = ['description', 'runs', 0, 'text'];
const carousel_title = [
  'header',
  'musicCarouselShelfBasicHeaderRenderer',
  'title',
  'runs',
  0
];
const mtrir = 'musicTwoRowItemRenderer';
const mrlir = 'musicResponsiveListItemRenderer';
const n_title = ['title', 'runs', 0]; //titile
const navigation_browse = ['navigationEndpoint', 'browseEndpoint'];
const page_type = [
  'browseEndpointContextSupportedConfigs',
  'browseEndpointContextMusicConfig',
  'pageType'
];
const navigation_watch_playlist_id = [
  'navigationEndpoint',
  'watchPlaylistEndpoint',
  'playlistId'
];
const audio_watch_playlist_id = [
  ...menu_items,
  0,
  'menuNavigationItemRenderer',
  ...navigation_watch_playlist_id
];
const title_text = ['title', 'runs', 0, 'text'];
const thumbnail_renderer = [
  'thumbnailRenderer',
  'musicThumbnailRenderer',
  'thumbnail',
  'thumbnails'
];
const navigation_playlist_id = [
  'navigationEndpoint',
  'watchEndpoint',
  'playlistId'
];
const navigation_video_id = ['navigationEndpoint', 'watchEndpoint', 'videoId'];
const subtitle2 = ['subtitle', 'runs', 2, 'text'];
const navigation_browse_id = [
  'navigationEndpoint',
  'browseEndpoint',
  'browseId'
];

const text_run_navigation_browse_id = [];

const subtitle_badge_label = [
  'subtitleBadges',
  0,
  'musicInlineBadgeRenderer',
  'accessibilityData',
  'accessibilityData',
  'label'
];
const text_run_text = ['text', 'runs', 0, 'text'];
const text_run = ['text', 'runs', 0];
const badge_label = [
  'badges',
  0,
  'musicInlineBadgeRenderer',
  'accessibilityData',
  'accessibilityData',
  'label'
];
const thumbnail = ['thumbnail', 'thumbnails'];
const thumbnails = [
  'thumbnail',
  'musicThumbnailRenderer',
  'thumbnail',
  'thumbnails'
];

const navigation_video_type = [
  'watchEndpoint',
  'watchEndpointMusicSupportedConfigs',
  'watchEndpointMusicConfig',
  'musicVideoType'
];
const toggle_menu = 'toggleMenuServiceItemRenderer';
const List<dynamic> menu_items = ['menu', 'menuRenderer', 'items'];
const menu_service = ['menuServiceItemRenderer', 'serviceEndpoint'];
const play_button = [
  'overlay',
  'musicItemThumbnailOverlayRenderer',
  'content',
  'musicPlayButtonRenderer'
];
const menu_like_status = [
  'menu',
  'menuRenderer',
  'topLevelButtons',
  0,
  'likeButtonRenderer',
  'likeStatus'
];
const List<dynamic> section_list_item = ['sectionListRenderer', 'contents', 0];
const List<dynamic> thumnail_cropped = [
  'thumbnail',
  'croppedSquareThumbnailRenderer',
  'thumbnail',
  'thumbnails'
];
const subtitle = ['subtitle', 'runs', 0, 'text'];
const subtitle3 = ['subtitle', 'runs', 4, 'text'];
const feedback_token = ['feedbackEndpoint', 'feedbackToken'];
const musicPlaylistShelfRenderer = [
  "contents",
  "twoColumnBrowseResultsRenderer",
  "secondaryContents",
  "sectionListRenderer",
  "contents",
  0,
  "musicPlaylistShelfRenderer",
];

List<Map<String, dynamic>> parseMixedContent(List<dynamic> rows) {
  List<Map<String, dynamic>> items = [];
  //inspect(rows);

  for (var row in rows) {
    dynamic title;
    dynamic contents = [];
    if (description_shelf[0] == row.keys.first.toString()) {
      var results = nav(row, description_shelf);
      title = nav(results, ['header', 'runs', 0, 'text']);
      contents = nav(results, description);
    } else {
      var results = row.values.first;
      if (!results.containsKey('contents')) {
        continue;
      }
      title = nav(results, carousel_title + ['text']);

      for (var result in results['contents']) {
        var data = nav(result, [mtrir]);
        dynamic content;
        if (data != null) {
          var pageType = nav(data, n_title + navigation_browse + page_type,
              noneIfAbsent: true, funName: "mixed1");
          if (pageType == null) {
            if (nav(data, navigation_watch_playlist_id) != null) {
              //  content = parseWatchPlaylistHome(data);
            } else {
              content = parseSong(data);
            }
          } else if (pageType == "MUSIC_PAGE_TYPE_ALBUM") {
            content = parseAlbum(data, reqAlbumObj: false);
          } else if (pageType == "MUSIC_PAGE_TYPE_ARTIST") {
            content = parseRelatedArtist(data);
          } else if (pageType == "MUSIC_PAGE_TYPE_PLAYLIST") {
            content = parsePlaylist(data);
          }
        } else {
          data = nav(result, [mrlir]);
          content = parseSongFlat(data);
        }

        contents.add(content);
      }

      items.add({'title': title, 'contents': contents});
    }
  }
  return items;
}

dynamic parseVideo(dynamic result) {
  final runs = nav(result, ['subtitle', 'runs']);
  final runsLength = runs.length;
  final artistsLen = runsLength == 3 ? 1 : getDotSeparatorIndex(runs);
  return MediaItemBuilder.fromJson({
    'title': nav(result, title_text),
    'videoId': nav(result, navigation_video_id) ??
        nav(
          result,
          navigation_browse_id,
        ),
    'artists': parseSongArtistsRuns(runs.sublist(0, artistsLen)),
    'playlistId': nav(result, navigation_playlist_id),
    'thumbnails': nav(result, thumbnail_renderer),
    'views': runs[runs.length - 1]['text'].split(' ')[0]
  });
}

dynamic parseSingle(dynamic result) {
  dynamic year;
  try {
    year = int.parse(nav(result, subtitle));
  } catch (e) {
    year = nav(result, ["subtitle", "runs", 2, "text"]);
  }
  return Album.fromJson({
    'title': nav(result, title_text),
    'artists': [
      {'name': 'Single'}
    ],
    'audioPlaylistId': nav(result, audio_watch_playlist_id),
    'year': "${year ?? ""}",
    'browseId': nav(result, ['title', 'runs', 0, ...navigation_browse_id]),
    'thumbnails': nav(result, thumbnail_renderer),
    'description':
        (nav(result, ["subtitle", "runs"])).map((run) => run['text']).join('')
  });
}

MediaItem parseSong(Map<dynamic, dynamic> result) {
  //inspect(result);
  var song = {
    'title': nav(result, title_text),
    'videoId':
        nav(result, navigation_video_id) ?? nav(result, navigation_browse_id),
    'playlistId': nav(result, navigation_playlist_id,
        noneIfAbsent: true, funName: "parseSong"),
    'thumbnails': nav(result, thumbnail_renderer),
  };

  song.addAll(parseSongRuns(result['subtitle']['runs']));
  return MediaItemBuilder.fromJson(song);
}

Map<String, dynamic> parseSongRuns(List<dynamic> runs) {
  Map<String, dynamic> parsed = {'artists': []};
  for (int i = 0; i < runs.length; i++) {
    Map<String, dynamic> run = runs[i];
    if (i % 2 != 0) {
      // uneven items are always separators
      continue;
    }
    String text = run['text'];
    if (run.containsKey('navigationEndpoint')) {
      // artist or album
      Map<String, dynamic> item = {
        'name': text,
        'id': nav(run, navigation_browse_id,
            noneIfAbsent: true, funName: "parseSongRuns")
      };

      if (item['id'] != null &&
          (item['id'].startsWith('MPRE') ||
              item['id'].contains("release_detail"))) {
        // album
        parsed['album'] = item;
      } else {
        // artist
        parsed['artists'].add(item);
      }
    } else {
      RegExp regExp = RegExp(r"^\d([^ ])* [^ ]*$");
      if (regExp.hasMatch(text) && i > 0) {
        parsed['views'] = text.split(' ')[0];
      } else if (RegExp(r"^(\d+:)*\d+:\d+$").hasMatch(text)) {
        parsed['length'] = text;
        parsed['duration_seconds'] = parseDuration(text);
      } else if (RegExp(r"^\d{4}$").hasMatch(text)) {
        parsed['year'] = text;
      } else {
        // artist without id
        parsed['artists'].add({'name': text, 'id': null});
      }
    }
  }
  return parsed;
}

Album parseAlbum(Map<dynamic, dynamic> result, {bool reqAlbumObj = true}) {
  final List runs = nav(result, ['subtitle', 'runs']);
  final Map<String, dynamic> artistInfo = parseSongRuns(runs);
  Map albumMap = {
    'title': nav(result, title_text),
    'browseId': nav(result, n_title + navigation_browse_id),
    'thumbnails': nav(result, thumbnail_renderer),
    'audioPlaylistId': nav(result, audio_watch_playlist_id),
    'description':
        (nav(result, ["subtitle", "runs"])).map((run) => run['text']).join('')
    //'isExplicit': nav(result, subtitle_badge_label, noneIfAbsent: true) != null,
  };
  albumMap.addAll(artistInfo);
  return Album.fromJson(albumMap);
}

Artist parseRelatedArtist(Map<String, dynamic> data) {
  return Artist.fromJson({
    'artist': nav(data, title_text),
    'browseId': nav(data, n_title + navigation_browse_id),
    'thumbnails': nav(data, thumbnail_renderer),
  });
}

Playlist parsePlaylist(Map<String, dynamic> data) {
  //inspect(data);
  Map<String, dynamic> playlist = {
    'title': nav(data, title_text),
    'playlistId': nav(data, ['title', 'runs', 0] + navigation_browse_id),
    'thumbnails': nav(data, thumbnail_renderer)
  };

  var subtitle = data['subtitle'];
  if (subtitle.containsKey('runs')) {
    var runs = subtitle['runs'];
    playlist['description'] = runs.map((run) => run['text']).join('');
    if (runs.length == 3 && RegExp(r'\d+ ').hasMatch(nav(data, subtitle2))) {
      playlist['count'] = nav(data, subtitle2).split(' ')[0];
      playlist['author'] = parseSongArtistsRuns(runs.sublist(0, 1));
    }
  }

  return Playlist.fromJson(playlist);
}

List<dynamic> parseSongArtistsRuns(List<dynamic> runs) {
  //print(runs);
  List<Map<String, dynamic>> artists = [];
  int n = (runs.length / 2).floor() + 1;
  for (var j = 0; j < n; j++) {
    artists.add({
      'name': runs[j * 2]['text'],
      'id': nav(runs[j * 2], navigation_browse_id,
          noneIfAbsent: false, funName: "parseSongArtistsRuns"),
    });
  }
  return artists;
}

MediaItem parseSongFlat(Map<String, dynamic> data) {
  //print(data);
  List<Map<String, dynamic>> columns = [];
  for (int i = 0; i < data['flexColumns'].length; i++) {
    columns.add(getFlexColumnItem(data, i));
  }

  Map<String, dynamic> song = {
    'title': nav(columns[0], text_run_text),
    'videoId': nav(columns[0], text_run + navigation_video_id,
            noneIfAbsent: true, funName: "parseSongFlat") ??
        nav(columns[0], text_run + navigation_browse_id,
            noneIfAbsent: true, funName: "parseSongFlat"),
    'artists': parseSongArtists(data, 1),
    'thumbnails': nav(data, thumbnails),
    //'isExplicit': nav(data, badge_label, noneIfAbsent: true) != null
  };
//checkpoint .contains
  if (columns.length > 2 && columns[2].isNotEmpty) {
    if (nav(columns[2], text_run).containsKey('navigationEndpoint')) {
      song['album'] = {
        'name': nav(columns[2], text_run_text),
        'id': nav(columns[2], text_run + navigation_browse_id)
      };
    }
  }

  return MediaItemBuilder.fromJson(song);
}

List<dynamic>? parseSongArtists(Map<String, dynamic> data, int index) {
  final flexItem = getFlexColumnItem(data, index);
  // Never null — empty map means missing column.
  if (flexItem.isEmpty) {
    return null;
  }
  final runs = flexItem['text']['runs'];
  return parseSongArtistsRuns(runs);
}

Map<String, dynamic> getFlexColumnItem(Map<String, dynamic> item, int index) {
  final flexColumns = item['flexColumns'];
  // multi-row podcast episodes and some other cards have no flexColumns
  if (flexColumns is! List || flexColumns.length <= index) {
    return {};
  }
  final renderer =
      flexColumns[index]['musicResponsiveListItemFlexColumnRenderer'];
  if (renderer is! Map ||
      !renderer.containsKey('text') ||
      renderer['text'] is! Map ||
      !renderer['text'].containsKey('runs')) {
    return {};
  }

  return Map<String, dynamic>.from(renderer);
}

Map<String, dynamic> parseWatchPlaylistHome(Map<dynamic, dynamic> data) {
  return {
    'title': nav(data, title_text),
    'playlistId': nav(data, navigation_watch_playlist_id),
    'thumbnails': nav(data, thumbnail_renderer),
  };
}

//For Song Watch Playlist

List<dynamic> parseWatchPlaylist(List<dynamic> results) {
  final tracks = [];
  const PPVWR = 'playlistPanelVideoWrapperRenderer';
  const PPVR = 'playlistPanelVideoRenderer';
  for (var result in results) {
    Map<String, dynamic>? counterpart;
    if (result.containsKey(PPVWR)) {
      counterpart =
          result[PPVWR]['counterpart'][0]['counterpartRenderer'][PPVR];
      result = result[PPVWR]['primaryRenderer'];
    }
    if (!result.containsKey(PPVR)) {
      continue;
    }
    final data = result[PPVR];
    if (data.containsKey('unplayableText')) {
      continue;
    }
    final track = parseWatchTrack(data);
    if (counterpart != null) {
      final cp = parseWatchTrack(counterpart);
      track['counterpart'] = cp;
      // A music video's own thumbnail is a 16:9 i.ytimg frame; its ATV audio
      // counterpart carries the real square cover (lh3). Prefer the square
      // cover for display (like RiPlay's song rows) without changing which
      // videoId actually plays.
      final cpThumbs = cp['thumbnails'];
      if (cpThumbs is List && cpThumbs.isNotEmpty) {
        track['thumbnails'] = cpThumbs;
      }
    }
    tracks.add(MediaItemBuilder.fromJson(track));
  }
  return tracks;
}

Map<String, dynamic> parseWatchTrack(Map<String, dynamic> data) {
  final songInfo = parseSongRuns(data['longBylineText']['runs']);

  final track = {
    'videoId': data['videoId'],
    'title': nav(data, title_text),
    'length': nav(data, ['lengthText', 'runs', 0, 'text']),
    'thumbnails': nav(data, thumbnail),
    'videoType': nav(data, ['navigationEndpoint'] + navigation_video_type),
  };
  track.addAll(songInfo);
  return track;
}

String? getTabBrowseId(Map<String, dynamic> watchNextRenderer, int tabId) {
  if (!watchNextRenderer['tabs'][tabId]['tabRenderer']
      .containsKey('unselectable')) {
    return watchNextRenderer['tabs'][tabId]['tabRenderer']['endpoint']
        ['browseEndpoint']['browseId'];
  } else {
    return null;
  }
}

///Parse playlist songs, Also used in Album Song parsing
///
///[dynamic album,dynamic artists] used in Album case
List<dynamic> parsePlaylistItems(List<dynamic> results,
    {List<List<dynamic>>? menuEntries,
    dynamic thumbnailsM,
    dynamic artistsM,
    String? albumYear,
    dynamic albumIdName,
    bool isAlbum = false}) {
  List<MediaItem> songs = [];

  //int count = 1;
  for (dynamic result in results) {
    // count += 1;
    if (!result.containsKey('musicResponsiveListItemRenderer')) {
      continue;
    }
    dynamic data = result['musicResponsiveListItemRenderer'];
    String? videoId;
    String? trackDetails;

    videoId = nav(data, ['playlistItemData', 'videoId']);

    if (videoId == null && isAlbum) {
      final creditId = nav(data, [
        'menu',
        'menuRenderer',
        'items',
        5,
        'menuNavigationItemRenderer',
        'navigationEndpoint',
        'browseEndpoint',
        'browseId'
      ]);
      videoId = creditId?.split("MPTC")[1];
    }

    if (isAlbum) {
      // Contains track number and total tracks
      trackDetails = data?["index"] != null
          ? "${nav(data, ['index', 'runs', 0, 'text'])}/${results.length}"
          : null;
    }

    // if the item has a menu, find its setVideoId
    if (videoId == null) {
      if (data.containsKey('menu')) {
        for (dynamic item in nav(data, menu_items)) {
          if (item.containsKey('menuServiceItemRenderer')) {
            dynamic menuService = nav(item, menu_service);
            //inspect(menuService);

            if (menuService.containsKey('playlistEditEndpoint')) {
              videoId = menuService['playlistEditEndpoint']['actions'][0]
                  ['removedVideoId'];
              // print("$videoId");
            }
          }
        }
      }
    }

    // if item is not playable, the videoId was retrieved above
    if (videoId == null && nav(data, play_button) != null) {
      if (nav(data, play_button).containsKey('playNavigationEndpoint')) {
        videoId = nav(data, play_button)['playNavigationEndpoint']
            ['watchEndpoint']['videoId'];
      }
    }

    String? title = getItemText(data, 0);
    if (title == 'Song deleted') {
      continue;
    }

    List? artists = parseSongArtists(data, 1);

    dynamic album = isAlbum ? albumIdName : parseSongAlbum({...data}, 2);

    dynamic duration;
    if (data.containsKey('fixedColumns')) {
      if (getFixedColumnItem(data, 0)!['text'].containsKey('simpleText')) {
        duration = getFixedColumnItem(data, 0)!['text']['simpleText'];
      } else {
        duration = getFixedColumnItem(data, 0)!['text']['runs'][0]['text'];
      }
    }

    dynamic thumbnails_;
    if (data.containsKey('thumbnail')) {
      thumbnails_ = nav(data, thumbnails);
    }

    bool isAvailable = true;
    if (data.containsKey('musicItemRendererDisplayPolicy')) {
      isAvailable = data['musicItemRendererDisplayPolicy'] !=
          'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT';
    }

    //print('here');
    dynamic song = {
      'videoId': videoId,
      'title': title,
      'album': album,
      'artists': artists ?? artistsM,
      'thumbnails': isAlbum ? thumbnailsM : thumbnails_ ?? thumbnailsM,
      'isAvailable': isAvailable,
      'trackDetails': trackDetails
    };

    if (duration != null) {
      song['length'] = duration;
      song['duration_seconds'] = parseDuration(duration);
    }

    if (menuEntries != null) {
      for (final List<dynamic> menuEntry in menuEntries) {
        song[menuEntry.last] = nav(data,
            menu_items + menuEntry.map((e) => e).whereType<String>().toList());
      }
    }
    if (song['videoId'] != null) {
      songs.add(MediaItemBuilder.fromJson(song));
    }
  }
  return songs;
}

Map<String, dynamic>? parseSongAlbum(Map<String, dynamic> data, int index) {
  Map<String, dynamic> flexItem = getFlexColumnItem(data, index);
  // print("here");
  if (flexItem.isNotEmpty) {
    return {
      'name': getItemText(data, index),
      'id': getBrowseId(flexItem, 0),
    };
  }
  return null;
}

String? getBrowseId(Map<String, dynamic> item, int index) {
  if (item['text']['runs'][index].containsKey('navigationEndpoint')) {
    return nav(item['text']['runs'][index], navigation_browse_id);
  }
  return null;
}

Map<String, dynamic> parseSongMenuTokens(Map<String, dynamic> item) {
  Map<String, dynamic> toggleMenu = item[toggle_menu];
  String serviceType = toggleMenu['defaultIcon']['iconType'];
  Map<String, dynamic> libraryAddToken =
      nav(toggleMenu, ['defaultServiceEndpoint', ...feedback_token]);
  Map<String, dynamic> libraryRemoveToken =
      nav(toggleMenu, ['toggledServiceEndpoint', ...feedback_token]);

  if (serviceType == "LIBRARY_REMOVE") {
    // swap if already in library
    Map<String, dynamic> temp = libraryAddToken;
    libraryAddToken = libraryRemoveToken;
    libraryRemoveToken = temp;
  }

  return {'add': libraryAddToken, 'remove': libraryRemoveToken};
}

dynamic nav(dynamic root, List items,
    {bool noneIfAbsent = false, String funName = "d"}) {
  try {
    dynamic res = root;
    for (final item in items) {
      res = res[item];
    }
    return res;
  } catch (e) {
    return null;
  }
}

//search parsers
dynamic parseTopResult(
    Map<String, dynamic> data, List<String> searchResultTypes) {
  Map<String, dynamic> searchResult = {};
  String? resultType =
      getSearchResultType(nav(data, subtitle), searchResultTypes);
  searchResult['resultType'] = resultType;

  if (resultType == 'artist') {
    String? subscribers = nav(data, subtitle2);
    if (subscribers != null) {
      searchResult['subscribers'] = subscribers.split(' ')[0];
    }
    Map<String, dynamic> artistInfo =
        parseSongRuns(nav(data, ['title', 'runs']));
    searchResult.addAll(artistInfo);
  }

  if (resultType == 'song' || resultType == 'video' || resultType == 'album') {
    searchResult['title'] = nav(data, title_text);
    List runs = nav(data, ['subtitle', 'runs']);
    List songInfoRuns = runs.sublist(2);
    Map<String, dynamic> songInfo = parseSongRuns(songInfoRuns);
    searchResult.addAll(songInfo);
  }

  searchResult['thumbnails'] = nav(data, thumbnails);

  if (resultType == 'song' || resultType == 'video') {
    return MediaItemBuilder.fromJson(searchResult);
  } else if (resultType == 'playlist') {
    return Playlist.fromJson(searchResult);
  } else if (resultType == 'album') {
    return Album.fromJson(searchResult);
  } else if (resultType == 'Artist') {
    return Artist.fromJson(searchResult);
  }
  return searchResult;
}

String? getSearchResultType(
    String? resultTypeLocal, List<String> resultTypesLocal) {
  if (resultTypeLocal == null) {
    return null;
  }
  List<String> resultTypes = [
    'artist',
    'playlist',
    'song',
    'video',
    'station',
    'podcast',
    'episode',
  ];
  resultTypeLocal = resultTypeLocal.toLowerCase();
  if (!resultTypesLocal.contains(resultTypeLocal)) {
    // default to album for unknown labels (Single, EP, …) unless podcast-ish
    if (resultTypeLocal.contains('podcast')) return 'podcast';
    if (resultTypeLocal.contains('episode')) return 'episode';
    return 'album';
  } else {
    int index = resultTypesLocal.indexOf(resultTypeLocal);
    if (index >= 0 && index < resultTypes.length) {
      return resultTypes[index];
    }
    // Prefer matching by name when local labels map 1:1
    if (resultTypes.contains(resultTypeLocal)) return resultTypeLocal;
    return 'album';
  }
}

List<dynamic> parseSearchResults(List<dynamic> results,
    List<String> searchResultTypes, String? resultType, String category) {
  return results
      .map((result) {
        // Podcast search often returns two-row cards
        if (result['musicTwoRowItemRenderer'] != null &&
            (resultType == 'podcast' ||
                category.toLowerCase().contains('podcast'))) {
          return parsePodcastTwoRow(result['musicTwoRowItemRenderer']);
        }
        final data = result['musicResponsiveListItemRenderer'];
        if (data == null) return null;
        return parseSearchResult(data, searchResultTypes, resultType, category);
      })
      .whereType<dynamic>()
      .toList();
}

dynamic parseSearchResult(Map<String, dynamic> data,
    List<String> searchResultTypes, String? resultType, String? category) {
  if ((resultType != null && resultType.contains("playlist")) ||
      (category != null && category.contains("playlists"))) {
    resultType = 'playlist';
  }
  if ((resultType != null && resultType.contains('podcast')) ||
      (category != null && category.toLowerCase().contains('podcasts'))) {
    resultType = 'podcast';
  }
  if ((resultType != null && resultType.contains('episode')) ||
      (category != null && category.toLowerCase().contains('episode'))) {
    resultType = 'episode';
  }
  int defaultOffset = (resultType == null) ? 2 : 0;
  Map<String, dynamic> searchResult = {'category': category};
  String? videoType = nav(data,
      [...play_button, 'playNavigationEndpoint', ...navigation_video_type]);
  if (videoType == 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE') {
    resultType = 'episode';
  } else if (videoType != null && resultType != 'episode') {
    resultType = (videoType == 'MUSIC_VIDEO_TYPE_ATV') ? 'song' : 'video';
  }

  // Infer podcast from browse id prefix when type unknown
  final browseGuess = nav(data, navigation_browse_id)?.toString();
  if (resultType == null &&
      browseGuess != null &&
      browseGuess.startsWith('MPSP')) {
    resultType = 'podcast';
  }

  resultType = ((resultType == null)
      ? getSearchResultType(getItemText(data, 1), searchResultTypes)
      : resultType)!;
  searchResult['resultType'] = resultType;

  if (resultType != 'artist') {
    searchResult['title'] = getItemText(data, 0);
  }

  if (resultType == 'artist') {
    searchResult['artist'] = getItemText(data, 0);
    final list = data['flexColumns'][1]
        ['musicResponsiveListItemFlexColumnRenderer']['text']['runs'];
    searchResult['subscribers'] = list.length < 2 ? "" : list[2];
    ['text'];
    //final x = parseMenuPlaylists(data, searchResult);
  } else if (resultType == 'album') {
    searchResult['type'] = getItemText(data, 1);
    searchResult['audioPlaylistId'] = nav(data, audio_watch_playlist_id);
    try {
      final list = data['flexColumns'][1]
          ['musicResponsiveListItemFlexColumnRenderer']['text']['runs'];
      searchResult['description'] = list.map((run) => run['text']).join('');
    } catch (e) {}
  } else if (resultType == 'podcast') {
    searchResult['description'] = 'Podcast';
    searchResult['kind'] = 'podcast';
    final browseId = nav(data, navigation_browse_id)?.toString() ??
        getItemText(data, 0); // fallback unused
    searchResult['browseId'] = browseId;
    searchResult['playlistId'] = browseId;
    // Channel / author in second column when present
    try {
      final flex1 = getFlexColumnItem(data, 1);
      // getFlexColumnItem never returns null (uses {} when missing).
      if (flex1.isNotEmpty) {
        final runs = flex1['text']?['runs'] as List? ?? [];
        if (runs.isNotEmpty) {
          searchResult['description'] = runs.map((r) => r['text']).join('');
        }
      }
    } catch (_) {}
  } else if (resultType == 'episode') {
    searchResult['videoId'] = nav(data, [
          ...play_button,
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]) ??
        nav(data, ['playlistItemData', 'videoId']) ??
        nav(data, ['onTap', 'watchEndpoint', 'videoId']);
    searchResult['videoType'] = videoType ?? 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE';
    try {
      final flex1 = getFlexColumnItem(data, 1);
      // getFlexColumnItem returns a non-null Map; only nested fields are nullable.
      final runs = flex1['text']?['runs'] as List? ?? [];
      // podcast name often in runs
      String? podcastName;
      for (final run in runs) {
        final bid = nav(run, navigation_browse_id)?.toString();
        if (bid != null && bid.startsWith('MPSP')) {
          podcastName = run['text'];
          searchResult['playlistId'] = bid;
          break;
        }
      }
      if (podcastName == null && runs.isNotEmpty) {
        podcastName = runs.length > 2 ? runs[2]['text'] : runs[0]['text'];
      }
      searchResult['artists'] = [
        {'name': podcastName ?? 'Podcast', 'id': searchResult['playlistId']}
      ];
      if (runs.isNotEmpty) {
        searchResult['date'] = runs[0]['text'];
      }
    } catch (_) {
      searchResult['artists'] = [
        {'name': 'Podcast', 'id': null}
      ];
    }
  } else if (resultType.contains('playlist')) {
    List<dynamic> flexItem = getFlexColumnItem(data, 1)['text']['runs'];
    bool hasAuthor = (flexItem.length == defaultOffset + 3);
    searchResult['itemCount'] =
        nav(flexItem, [defaultOffset + (hasAuthor ? 2 : 0), 'text'])
            .split(' ')[0];
    searchResult['description'] =
        hasAuthor ? nav(flexItem, [defaultOffset, 'text']) : null;
  } else if (resultType == 'station') {
    searchResult['videoId'] =
        nav(data, navigation_video_id) ?? nav(data, navigation_browse_id);
    searchResult['playlistId'] = nav(data, navigation_playlist_id);
  } else if (resultType == 'song') {
    searchResult['album'] = null;
  } else if (resultType == 'upload') {
    String? browseId = nav(data, navigation_browse_id);
    if (browseId == null) {
      List<dynamic> flexItems = [
        nav(getFlexColumnItem(data, 0), ['text', 'runs']),
        nav(getFlexColumnItem(data, 1), ['text', 'runs'])
      ];
      if (flexItems[0] != null) {
        searchResult['videoId'] = nav(flexItems[0][0], navigation_video_id) ??
            nav(flexItems[0][0], navigation_browse_id);
        searchResult['playlistId'] =
            nav(flexItems[0][0], navigation_playlist_id);
      }
      if (flexItems[1] != null) {
        searchResult.addAll(parseSongRuns(flexItems[1]));
      }
      searchResult['resultType'] = 'song';
    } else {
      searchResult['browseId'] = browseId;
      if (searchResult['browseId'].contains('artist')) {
        searchResult['resultType'] = 'artist';
      } else {
        Map<String, dynamic> flexItem2 = getFlexColumnItem(data, 1);
        List<dynamic> runs = [
          for (int i = 0; i < flexItem2['text']['runs'].length; i++)
            if (i % 2 == 0) flexItem2['text']['runs'][i]['text']
        ];
        if (runs.length > 1) {
          searchResult['artist'] = runs[1];
        }
        if (runs.length > 2) {
          searchResult['releaseDate'] = runs[2];
        }
        searchResult['resultType'] = 'album';
      }
    }
  }
  if ((['song', 'video']).contains(resultType)) {
    searchResult['videoId'] = nav(data,
        [...play_button, 'playNavigationEndpoint', 'watchEndpoint', 'videoId']);
    searchResult['videoType'] = videoType;
  }

  if ((['song', 'video', 'album']).contains(resultType)) {
    searchResult['length'] = null;
    searchResult['year'] = null;
    final flexItem = getFlexColumnItem(data, 1);
    final runs = (flexItem['text']['runs']);
    final songInfo = parseSongRuns(runs);
    searchResult.addAll(songInfo);
  }

  if ((['artist', 'album', 'playlist', 'podcast']).contains(resultType)) {
    searchResult['browseId'] ??= nav(data, navigation_browse_id);
    searchResult['playlistId'] ??= searchResult['browseId'];
    if (searchResult['browseId'] == null && resultType != 'podcast') {
      return {};
    }
  }

  if ((['song', 'album']).contains(resultType)) {
    searchResult['isExplicit'] = nav(data, badge_label);
  }

  searchResult['thumbnails'] = nav(data, thumbnails);

  if (resultType == 'song' ||
      resultType == 'video' ||
      resultType == 'episode') {
    if (searchResult['videoId'] != null) {
      return MediaItemBuilder.fromJson(searchResult);
    }
    return;
  } else if (resultType == 'podcast') {
    if (searchResult['playlistId'] == null &&
        searchResult['browseId'] == null) {
      return;
    }
    searchResult['playlistId'] ??= searchResult['browseId'];
    searchResult['thumbnails'] ??= [
      {'url': Playlist.thumbPlaceholderUrl}
    ];
    return Playlist.fromJson({
      ...searchResult,
      'kind': 'podcast',
      'description': searchResult['description'] ?? 'Podcast',
    });
  } else if (resultType.contains('playlist')) {
    return Playlist.fromJson(searchResult);
  } else if (resultType == 'album') {
    return Album.fromJson(searchResult);
  } else if (resultType == 'artist') {
    return Artist.fromJson(searchResult);
  }

  return searchResult;
}

/// Two-row podcast card from search / channel pages.
Playlist? parsePodcastTwoRow(Map<String, dynamic> data) {
  try {
    final browseId = nav(data, n_title + navigation_browse_id)?.toString() ??
        nav(data, navigation_browse_id)?.toString();
    if (browseId == null) return null;
    final title = nav(data, title_text) ?? '';
    final thumbs = nav(data, thumbnail_renderer) ??
        nav(data, thumbnails) ??
        [
          {'url': Playlist.thumbPlaceholderUrl}
        ];
    String description = 'Podcast';
    final subtitleRuns = nav(data, ['subtitle', 'runs']) as List?;
    if (subtitleRuns != null && subtitleRuns.isNotEmpty) {
      description = subtitleRuns.map((r) => r['text']).join('');
    }
    return Playlist.fromJson({
      'title': title,
      'playlistId': browseId,
      'browseId': browseId,
      'thumbnails': thumbs,
      'description': description,
      'kind': 'podcast',
      'isCloudPlaylist': true,
    });
  } catch (_) {
    return null;
  }
}

/// Episodes under a podcast musicShelf.
///
/// YouTube Music currently returns podcast episodes as
/// `musicMultiRowListItemRenderer` (detailed cards). Older responses (and
/// some channel/explore shelves) still use `musicResponsiveListItemRenderer`.
///
/// [fallbackThumbs] is the podcast cover used when an episode has no art.
List<MediaItem> parsePodcastEpisodes(List contents, {dynamic fallbackThumbs}) {
  final episodes = <MediaItem>[];
  for (final item in contents) {
    if (item is! Map) continue;
    final data = item['musicMultiRowListItemRenderer'] ??
        item['musicResponsiveListItemRenderer'];
    if (data == null || data is! Map) continue;
    final parsed = parseEpisodeItem(Map<String, dynamic>.from(data),
        fallbackThumbs: fallbackThumbs);
    if (parsed != null) episodes.add(parsed);
  }
  return episodes;
}

MediaItem? parseEpisodeItem(Map<String, dynamic> data,
    {dynamic fallbackThumbs}) {
  try {
    final videoId = nav(data, [
          'onTap',
          'watchEndpoint',
          'videoId',
        ]) ??
        nav(data, [
          ...play_button,
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]) ??
        nav(data, ['playlistItemData', 'videoId']);
    if (videoId == null) return null;

    final title = nav(data, title_text) ?? getItemText(data, 0) ?? 'Episode';
    // Episode cards often ship a 16:9 video frame (i.ytimg.com/vi/...). Prefer
    // the podcast's square cover when we have it so list tiles show real art,
    // not a stretched video screenshot.
    final episodeThumbs = nav(data, thumbnails) ??
        nav(data, thumbnail_renderer) ??
        nav(data, thumbnail);
    final thumbs = _preferSquareThumbs(episodeThumbs, fallbackThumbs) ??
        [
          {'url': Playlist.thumbPlaceholderUrl}
        ];
    final durationText = nav(data, [
          'playbackProgress',
          'musicPlaybackProgressRenderer',
          'durationText',
          'runs',
          1,
          'text',
        ]) ??
        nav(data, [
          'playbackProgress',
          'musicPlaybackProgressRenderer',
          'durationText',
          'runs',
          0,
          'text',
        ]) ??
        // multi-row also uses playbackProgressText as a twin of durationText
        nav(data, [
          'playbackProgress',
          'musicPlaybackProgressRenderer',
          'playbackProgressText',
          'runs',
          1,
          'text',
        ]);
    // Don't name this local "description" — shadows the top-level path const.
    final descriptionText = nav(data, description);
    final date = nav(data, subtitle);

    // Prefer podcast name as artist
    String artistName = 'Podcast';
    final secondTitle = nav(data, ['secondTitle', 'runs', 0, 'text']);
    if (secondTitle != null) {
      artistName = secondTitle;
    } else {
      try {
        final flex1 = getFlexColumnItem(data, 1);
        final runs = flex1['text']?['runs'] as List?;
        if (runs != null && runs.isNotEmpty) {
          artistName = runs.map((r) => r['text']).join('');
        }
      } catch (_) {}
    }

    return MediaItemBuilder.fromJson({
      'videoId': videoId,
      'title': title,
      'thumbnails': thumbs,
      'length': durationText,
      'duration': _parseLooseDurationSeconds(durationText),
      'artists': [
        {'name': artistName, 'id': null}
      ],
      'date': date,
      'description': descriptionText,
      'videoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
    });
  } catch (_) {
    return null;
  }
}

/// Prefer square podcast/playlist covers over landscape video frames.
dynamic _preferSquareThumbs(dynamic episodeThumbs, dynamic fallbackThumbs) {
  String? bestEp;
  if (episodeThumbs != null) {
    bestEp = Thumbnail.bestUrl(episodeThumbs, preferSquare: true);
  }
  String? bestCover;
  if (fallbackThumbs != null) {
    bestCover = Thumbnail.bestUrl(fallbackThumbs, preferSquare: true);
  }

  // If episode art is a video frame and we have a cover, use the cover.
  if (bestEp != null &&
      Thumbnail.isVideoFrameUrl(bestEp) &&
      bestCover != null &&
      bestCover.isNotEmpty) {
    return [
      {'url': bestCover}
    ];
  }
  if (bestEp != null && bestEp.isNotEmpty) {
    return [
      {'url': bestEp}
    ];
  }
  if (bestCover != null && bestCover.isNotEmpty) {
    return [
      {'url': bestCover}
    ];
  }
  return episodeThumbs ?? fallbackThumbs;
}

/// Parse an explore-shelf episode card (list or two-row).
MediaItem? parseExploreEpisode(dynamic item) {
  if (item is! Map) return null;
  if (item['musicResponsiveListItemRenderer'] != null) {
    return parseEpisodeItem(
        Map<String, dynamic>.from(item['musicResponsiveListItemRenderer']));
  }
  if (item['musicTwoRowItemRenderer'] != null) {
    final data = Map<String, dynamic>.from(item['musicTwoRowItemRenderer']);
    final videoId = nav(data, navigation_video_id) ??
        nav(data, [
          ...play_button,
          'playNavigationEndpoint',
          'watchEndpoint',
          'videoId',
        ]);
    if (videoId == null) return null;
    return MediaItemBuilder.fromJson({
      'videoId': videoId,
      'title': nav(data, title_text) ?? 'Episode',
      'thumbnails': nav(data, thumbnail_renderer) ??
          [
            {'url': Playlist.thumbPlaceholderUrl}
          ],
      'artists': [
        {
          'name': nav(data, subtitle) ?? 'Podcast',
          'id': null,
        }
      ],
      'videoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
    });
  }
  return null;
}

/// Accepts "3:45", "25 min", "1 hr 12 min", etc.
int? _parseLooseDurationSeconds(String? text) {
  if (text == null || text.isEmpty) return null;
  if (text.contains(':')) {
    return parseDuration(text);
  }
  final lower = text.toLowerCase();
  int seconds = 0;
  final hr = RegExp(r'(\d+)\s*hr').firstMatch(lower);
  final min = RegExp(r'(\d+)\s*min').firstMatch(lower);
  final sec = RegExp(r'(\d+)\s*sec').firstMatch(lower);
  if (hr != null) seconds += int.parse(hr.group(1)!) * 3600;
  if (min != null) seconds += int.parse(min.group(1)!) * 60;
  if (sec != null) seconds += int.parse(sec.group(1)!);
  if (seconds > 0) return seconds;
  final plain = int.tryParse(lower.trim());
  return plain;
}

//parse album Header
Map<String, dynamic> parseAlbumHeader(Map<String, dynamic> response) {
  Map<String, dynamic> header = nav(response, [
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
      ]) ??
      nav(response, ["header", "musicDetailHeaderRenderer"]);
  Map<String, dynamic> album = {
    'title': nav(header, title_text),
    'type': nav(header, subtitle),
    'thumbnails': nav(header, thumnail_cropped) ??
        nav(header,
            ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"])
  };

  album["description"] = nav(header, [
        "description",
        "musicDescriptionShelfRenderer",
        "description",
        "runs",
        0,
        "text"
      ]) ??
      (nav(header, ["subtitle", "runs"]))
          .map((item) => item.values.first)
          .toList()
          .join(" ");

  Map<String, dynamic> albumInfo =
      parseSongRuns(header['subtitle']['runs'].sublist(2));
  try {
    albumInfo.addAll(parseSongRuns(header["straplineTextOne"]['runs']));
  } catch (e) {}
  album.addAll(albumInfo);

  if (header['secondSubtitle']['runs'].length > 1) {
    album['trackCount'] = (header['secondSubtitle']['runs'][0]['text']);
    album['duration'] = header['secondSubtitle']['runs'][2]['text'];
  } else {
    album['duration'] = header['secondSubtitle']['runs'][0]['text'];
  }

  // add to library/uploaded

  album['audioPlaylistId'] =
      nav(response, ['microformat', "microformatDataRenderer", "urlCanonical"])
          .toString()
          .split("list=")[1];

  return album;
}

Map<String, dynamic> parseArtistContents(List results) {
  final Map<String, dynamic> navigationEndpointsNContent = {
    'Songs': null,
    'Videos': null,
    'Albums': null,
    'Singles': null
  };

  for (dynamic result in results) {
    if (result.containsKey('musicShelfRenderer')) {
      final title =
          nav(result, ['musicShelfRenderer', 'title', 'runs', 0])['text'];
      final browseEndpoint = nav(
          result, ['musicShelfRenderer', 'bottomEndpoint', 'browseEndpoint']);

      final contentList = nav(result, ['musicShelfRenderer', 'contents']);
      final content = parsePlaylistItems(contentList);

      if (browseEndpoint == null) {
        navigationEndpointsNContent[title] = {"content": content};
      } else {
        navigationEndpointsNContent[title] = {
          'browseId': browseEndpoint['browseId'],
          'params': browseEndpoint['params'],
          "content": content
        };
      }
    } else if (result.containsKey('musicCarouselShelfRenderer')) {
      final browseEndpoint = nav(result, [
        'musicCarouselShelfRenderer',
        'header',
        'musicCarouselShelfBasicHeaderRenderer',
        'moreContentButton',
        'buttonRenderer',
        'navigationEndpoint',
        'browseEndpoint'
      ]);

      final title = nav(result, [
        'musicCarouselShelfRenderer',
        'header',
        'musicCarouselShelfBasicHeaderRenderer',
        'title',
        'runs',
        0
      ])['text'];

      final contentList =
          nav(result, ['musicCarouselShelfRenderer', 'contents']);
      dynamic content = [];
      if (title == "Videos") {
        content = contentList
            .map((video) => parseVideo(video['musicTwoRowItemRenderer']))
            .toList();
      } else if (title == "Albums") {
        content = contentList
            .map((album) => parseAlbum(album['musicTwoRowItemRenderer']))
            .toList();
      } else if (title == "Singles") {
        content = contentList
            .map((single) => parseSingle(single['musicTwoRowItemRenderer']))
            .toList();
      } else if (title.toLowerCase().contains('featur')) {
        // "Featured on" — playlists that include this artist.
        content = contentList
            .map((pl) => parsePlaylist(pl['musicTwoRowItemRenderer']))
            .whereType<Playlist>()
            .toList();
      }

      // Normalise the "Featured on" shelf to a stable key.
      final key = title.toLowerCase().contains('featur') ? 'Featured' : title;
      if (browseEndpoint != null) {
        navigationEndpointsNContent[key] = {
          'browseId': browseEndpoint['browseId'],
          'params': browseEndpoint['params'],
          'content': content
        };
      } else {
        navigationEndpointsNContent[key] = {'content': content};
      }
    }
  }
  return navigationEndpointsNContent;
}

dynamic parseContentList(results, Function parseFunc) {
  var contents = [];
  for (dynamic result in results) {
    contents.add(parseFunc(result['musicTwoRowItemRenderer']));
  }

  return contents;
}

Map<String, dynamic> parseChartsItemBrowseId(dynamic result) {
  final title =
      nav(result, ["musicTwoRowItemRenderer", "title", "runs", 0, "text"]);
  final browseId = nav(result, [
    "musicTwoRowItemRenderer",
    "title",
    "runs",
    0,
    "navigationEndpoint",
    "browseEndpoint",
    "browseId"
  ]);
  if (title.contains('Trending')) {
    return {'title': "Trending", 'browseId': browseId};
  } else if (title.contains('Daily Top')) {
    return {'title': "Top Music Videos", 'browseId': browseId};
  } else {
    return {'title': title, 'browseId': browseId};
  }
}

Map<String, dynamic> parseChartsItem(dynamic result) {
  final contentList = nav(result, ['musicCarouselShelfRenderer', 'contents']);
  final String category = nav(result, [
    'musicCarouselShelfRenderer',
    'header',
    'musicCarouselShelfBasicHeaderRenderer',
    'title',
    ...run_text
  ]);
  if (category.contains('videos')) {
    final videoList = contentList
        .map((video) => parseVideo(video['musicTwoRowItemRenderer']))
        .toList();
    return {'title': category, 'contents': videoList};
  } else if (category.contains('artists')) {
    final artists = contentList
        .map((artist) =>
            parseChartsArtist(artist['musicResponsiveListItemRenderer']))
        .toList();
    return {'title': category, 'contents': artists};
  } else if (category.contains('Genres')) {
    final playlists = contentList
        .map((playlist) => parsePlaylist(playlist['musicTwoRowItemRenderer']))
        .toList();
    return {'title': category, 'contents': playlists};
  } else if (category.contains('Trending')) {
    final videoList = contentList
        .map((video) =>
            parseChartsTrending(video['musicResponsiveListItemRenderer']))
        .whereType<MediaItem>()
        .toList();
    return {'title': category, 'contents': videoList};
  }
  return {};
}

Artist parseChartsArtist(dynamic data) {
  final subscribers = getFlexColumnItem(data, 1);
  dynamic subs;
  if (subscribers.isNotEmpty) {
    subs = nav(subscribers, text_run_text).split(' ')[0];
  }

  final parsed = {
    'artist': nav(getFlexColumnItem(data, 0), text_run_text),
    'browseId': nav(data, navigation_browse_id),
    'subscribers': subs,
    'thumbnails': nav(data, thumbnails),
  };

  return Artist.fromJson(parsed);
}

MediaItem? parseChartsTrending(dynamic data) {
  final flex_0 = getFlexColumnItem(data, 0);
  final artists = parseSongArtists(data, 1);

  final video = {
    'title': nav(flex_0, text_run_text),
    'videoId': nav(
          flex_0,
          text_run + navigation_video_id,
        ) ??
        nav(data, ['playlistItemData', 'videoId']),
    'playlistId': nav(flex_0, text_run + navigation_playlist_id),
    'artists': artists,
    'thumbnails': nav(data, thumbnails),
  };
  if (video['videoId'] == null) {
    return null;
  }
  return MediaItemBuilder.fromJson(video);
}
