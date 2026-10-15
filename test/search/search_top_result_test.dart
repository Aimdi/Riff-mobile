import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/search_top_result.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/widgets/search_related_widgets.dart';

import '../fakes/fake_music_services.dart';

Map<String, dynamic> _run(String text, {String? browseId}) => {
      'text': text,
      if (browseId != null)
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId}
        },
    };

const _sep = {'text': ' • '};

final _thumbs = {
  'musicThumbnailRenderer': {
    'thumbnail': {
      'thumbnails': [
        {'url': 'https://lh3.googleusercontent.com/x=w120-h120', 'width': 120}
      ]
    }
  }
};

/// YouTube Music's "Top result" card, as its search answers it.
Map<String, dynamic> _card(
  String title,
  List<Map<String, dynamic>> subtitle, {
  String? browseId,
  String? videoId,
  String? videoType,
}) =>
    {
      'header': {
        'musicCardShelfHeaderBasicRenderer': {
          'title': {
            'runs': [_run('Top result')]
          }
        }
      },
      'thumbnail': _thumbs,
      'title': {
        'runs': [_run(title, browseId: browseId)]
      },
      'subtitle': {'runs': subtitle},
      if (videoId != null)
        'onTap': {
          'watchEndpoint': {
            'videoId': videoId,
            if (videoType != null)
              'watchEndpointMusicSupportedConfigs': {
                'watchEndpointMusicConfig': {'musicVideoType': videoType}
              },
          }
        },
    };

final _artistCard = _card(
    'Radiohead', [_run('Artist'), _sep, _run('10.5M subscribers')],
    browseId: 'UCr_iyUANcn9OX_yy9piYoLw');

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// YouTube Music's best match first in the search's All results, as its
/// own search page and Spotify's show their "Top result".
void main() {
  group('the card read', () {
    test('an artist', () {
      final a = SearchTopResult.parse(_artistCard) as Artist;
      expect(a.name, 'Radiohead');
      expect(a.browseId, 'UCr_iyUANcn9OX_yy9piYoLw');
      expect(a.subscribers, '10.5M subscribers');
      expect(SearchTopResult.kindOf(a), 'Artists');
    });

    test('a song, and a video', () {
      final song = SearchTopResult.parse(_card(
          'Creep',
          [
            _run('Song'),
            _sep,
            _run('Radiohead', browseId: 'UCr_iyUANcn9OX_yy9piYoLw'),
            _sep,
            _run('Pablo Honey', browseId: 'MPREb_abc'),
            _sep,
            _run('3:58'),
          ],
          videoId: 'XFkzRNyygfk',
          videoType: 'MUSIC_VIDEO_TYPE_ATV')) as MediaItem;
      expect(song.id, 'XFkzRNyygfk');
      expect(song.title, 'Creep');
      expect(song.artist, 'Radiohead');
      expect(song.album, 'Pablo Honey');
      expect(song.duration, const Duration(minutes: 3, seconds: 58));
      expect(SearchTopResult.kindOf(song), 'Songs');

      final video = SearchTopResult.parse(_card(
          'Creep (Official Video)',
          [
            _run('Video'),
            _sep,
            _run('Radiohead'),
            _sep,
            _run('1.2B views'),
          ],
          videoId: 'XFkzRNyygfk',
          videoType: 'MUSIC_VIDEO_TYPE_OMV')) as MediaItem;
      expect(SearchTopResult.kindOf(video), 'Videos');
    });

    test('an album or a single, a playlist, a podcast', () {
      final single = SearchTopResult.parse(_card(
          'Creep',
          [
            _run('Single'),
            _sep,
            _run('Radiohead', browseId: 'UCr_iyUANcn9OX_yy9piYoLw'),
            _sep,
            _run('1992'),
          ],
          browseId: 'MPREb_single')) as Album;
      expect(single.browseId, 'MPREb_single');
      expect(single.artists!.first['name'], 'Radiohead');
      expect(single.year, '1992');
      expect(SearchTopResult.kindOf(single), 'Albums');

      final list = SearchTopResult.parse(_card('Radiohead Essentials',
          [_run('Playlist'), _sep, _run('YouTube Music')],
          browseId: 'VLPL123')) as Playlist;
      expect(list.playlistId, 'VLPL123');
      expect(SearchTopResult.kindOf(list), 'Community playlists');

      final show = SearchTopResult.parse(_card(
          'The Daily', [_run('Podcast'), _sep, _run('NYT')],
          browseId: 'MPSPPL123')) as Playlist;
      expect(show.kind, 'podcast');
      expect(SearchTopResult.kindOf(show), 'Podcasts');
    });

    test('what it can\'t be shown as: nothing', () {
      // A kind the overview doesn't show, a card missing what it needs.
      expect(
          SearchTopResult.parse(
              _card('Someone', [_run('Profile')], browseId: 'UC1')),
          isNull);
      expect(
          SearchTopResult.parse(_card('Radiohead', [_run('Artist')])), isNull);
      expect(SearchTopResult.parse(_card('Creep', [_run('Song')])), isNull);
      expect(
          SearchTopResult.parse(
              _card('Creep', [_run('Album')], browseId: 'UCnotAnAlbum')),
          isNull);
      expect(SearchTopResult.parse({'title': 'garbled'}), isNull);
    });
  });

  test('the overview search keeps it, apart from its tabs', () async {
    final ms = MusicServices();
    ms.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {'musicCardShelfRenderer': _artistCard},
                        {
                          'musicShelfRenderer': {
                            'title': {
                              'runs': [_run('Songs')]
                            },
                            'contents': const [],
                          }
                        },
                      ]
                    }
                  }
                }
              }
            ]
          }
        }
      }));
    }));
    final all = await ms.search('radiohead');
    expect((all[SearchTopResult.key] as Artist).name, 'Radiohead');
    expect(all['Songs'], isEmpty);
    final songs = await ms.search('radiohead', filter: 'songs');
    expect(songs.containsKey(SearchTopResult.key), isFalse);
  });

  group('All results', () {
    late SearchResultScreenController c;

    setUp(() {
      Get.put<MusicServices>(FakeMusicServices());
      Get.put<SettingsScreenController>(_FakeSettings());
      c = Get.put(SearchResultScreenController());
    });
    tearDown(Get.reset);

    testWidgets('it comes first, and isn\'t listed again under its kind',
        (tester) async {
      final top = SearchTopResult.parse(_artistCard)!;
      final other = Artist(
          name: 'Thom Yorke',
          browseId: 'UC2',
          subscribers: '1M subscribers',
          thumbnailUrl: '');
      c.resultContent.value = {
        SearchTopResult.key: top,
        'Artists': [top, other],
      };
      c.railItems.value = ['Artists'];
      c.isResultContentFetced.value = true;
      await tester.pumpWidget(MaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: ResultWidget()),
      ));
      await tester.pump();

      expect(find.text('topResult'), findsOneWidget);
      expect(find.text('Radiohead'), findsOneWidget);
      expect(find.text('Thom Yorke'), findsOneWidget);
      // Above the Artists section.
      expect(tester.getTopLeft(find.text('topResult')).dy,
          lessThan(tester.getTopLeft(find.text('artists')).dy));
      expect(tester.getTopLeft(find.text('Radiohead')).dy,
          lessThan(tester.getTopLeft(find.text('artists')).dy));
      // The section of one has no View all.
      expect(find.text('viewAll'), findsOneWidget);
      // Not a tab of its own.
      expect(c.railItems, ['Artists']);
    });
  });
}
