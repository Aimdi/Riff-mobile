import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/explicit_content.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/search_recents.dart';
import 'package:harmonymusic/services/search_suggestions.dart';
import 'package:harmonymusic/services/search_top_result.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

import '../fakes/fake_music_services.dart';

const _radiohead = 'UCr_iyUANcn9OX_yy9piYoLw';

Map<String, dynamic> _r(String text, {String? browseId}) => {
      'text': text,
      if (browseId != null)
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId}
        },
    };

const _sep = {'text': ' • '};

Map<String, dynamic> _query(String q) => {
      'searchSuggestionRenderer': {
        'suggestion': {
          'runs': [
            {'text': q}
          ]
        },
        'navigationEndpoint': {
          'searchEndpoint': {'query': q}
        },
      }
    };

Map<String, dynamic> _browse(String id, String pageType) => {
      'browseEndpoint': {
        'browseId': id,
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': pageType}
        },
      }
    };

Map<String, dynamic> _watch(String id, String videoType) => {
      'watchEndpoint': {
        'videoId': id,
        'watchEndpointMusicSupportedConfigs': {
          'watchEndpointMusicConfig': {'musicVideoType': videoType}
        },
      }
    };

/// A suggested result, as YouTube Music lists it under the searches.
Map<String, dynamic> _row(String title, List<Map<String, dynamic>> subtitle,
        {required Map<String, dynamic> endpoint, bool explicit = false}) =>
    {
      'musicResponsiveListItemRenderer': {
        'thumbnail': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/x=w60-h60'}
              ]
            }
          }
        },
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [_r(title)]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {'runs': subtitle}
            }
          },
        ],
        'navigationEndpoint': endpoint,
        if (endpoint['watchEndpoint'] != null)
          'playlistItemData': {
            'videoId': endpoint['watchEndpoint']['videoId'],
          },
        if (explicit)
          'badges': [
            {
              'musicInlineBadgeRenderer': {
                'accessibilityData': {
                  'accessibilityData': {'label': 'Explicit'}
                }
              }
            }
          ],
      }
    };

final _response = {
  'contents': [
    {
      'searchSuggestionsSectionRenderer': {
        'contents': [
          _query('radiohead'),
          {
            'historySuggestionRenderer': {
              'suggestion': {
                'runs': [
                  {'text': 'old'}
                ]
              }
            }
          },
          _query('radiohead creep'),
        ]
      }
    },
    {
      'searchSuggestionsSectionRenderer': {
        'contents': [
          _row('Radiohead', [_r('Artist'), _sep, _r('10.5M subscribers')],
              endpoint: _browse(_radiohead, 'MUSIC_PAGE_TYPE_ARTIST')),
          _row(
              'Creep',
              [
                _r('Song'),
                _sep,
                _r('Radiohead', browseId: _radiohead),
                _sep,
                _r('Pablo Honey', browseId: 'MPREb_pablo'),
              ],
              endpoint: _watch('XFkzRNyygfk', 'MUSIC_VIDEO_TYPE_ATV'),
              explicit: true),
          _row(
              'OK Computer',
              [
                _r('Album'),
                _sep,
                _r('Radiohead', browseId: _radiohead),
                _sep,
                _r('1997'),
              ],
              endpoint: _browse('MPREb_okc', 'MUSIC_PAGE_TYPE_ALBUM')),
          _row('Creep (Official Video)',
              [_r('Video'), _sep, _r('Radiohead'), _sep, _r('1.2B views')],
              endpoint: _watch('XFkzRNyyg00', 'MUSIC_VIDEO_TYPE_OMV')),
          _row('Radiohead Essentials',
              [_r('Playlist'), _sep, _r('YouTube Music')],
              endpoint: _browse('VLPLessentials', 'MUSIC_PAGE_TYPE_PLAYLIST')),
          // A profile: nothing the search shows.
          _row('radiohead fan', [_r('Profile'), _sep, _r('@fan')],
              endpoint: _browse('UCfan', 'MUSIC_PAGE_TYPE_USER_CHANNEL')),
        ]
      }
    },
  ]
};

class _FakePlayer extends GetxController implements PlayerController {
  final played = <String>[];

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played.add('${source?.name}: ${mediaItems[index].title}');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// What YouTube Music suggests as you type, as its search box (and
/// Spotify's, Apple Music's, Metrolist's) shows it: the searches, then the
/// songs, artists and albums to play or open straight away.
void main() {
  group('what YouTube Music suggests', () {
    test('its searches, then what they would open', () {
      final s = SearchSuggestions.fromResponse(_response);
      expect(s.queries, ['radiohead', 'radiohead creep']);
      expect(s.items, hasLength(5));

      final artist = s.items[0] as Artist;
      expect(artist.name, 'Radiohead');
      expect(artist.browseId, _radiohead);

      final song = s.items[1] as MediaItem;
      expect(song.id, 'XFkzRNyygfk');
      expect(song.title, 'Creep');
      expect(song.artist, 'Radiohead');
      expect(song.album, 'Pablo Honey');
      expect(song.extras!['resultType'], 'song');
      expect(song.extras!['isExplicit'], isTrue);
      expect(song.artUri, isNotNull);

      final album = s.items[2] as Album;
      expect(album.browseId, 'MPREb_okc');
      expect(album.artists!.first['name'], 'Radiohead');
      expect(album.year, '1997');

      final video = s.items[3] as MediaItem;
      expect(video.extras!['resultType'], 'video');
      expect((s.items[4] as Playlist).playlistId, 'VLPLessentials');
    });

    test('in any language: by what it opens, not its label', () {
      final s = SearchSuggestions.fromResponse({
        'contents': [
          {
            'searchSuggestionsSectionRenderer': {
              'contents': [
                _row('Radiohead', [_r('Artiste')],
                    endpoint: _browse(_radiohead, 'MUSIC_PAGE_TYPE_ARTIST')),
                _row('Creep', [_r('Titre'), _sep, _r('Radiohead')],
                    endpoint: _watch('XFkzRNyygfk', 'MUSIC_VIDEO_TYPE_ATV')),
              ]
            }
          }
        ]
      });
      expect(s.items[0], isA<Artist>());
      expect((s.items[1] as MediaItem).extras!['resultType'], 'song');

      // The Top result card too, when its label isn't English.
      final top = SearchTopResult.parse({
        'title': {
          'runs': [
            {
              'text': 'Radiohead',
              'navigationEndpoint':
                  _browse(_radiohead, 'MUSIC_PAGE_TYPE_ARTIST'),
            }
          ]
        },
        'subtitle': {
          'runs': [_r('Künstler')]
        },
      });
      expect((top as Artist).browseId, _radiohead);
    });

    test('garbled or missing: nothing', () {
      expect(SearchSuggestions.fromResponse(null).queries, isEmpty);
      expect(SearchSuggestions.fromResponse({'contents': 'x'}).items, isEmpty);
      expect(
          SearchSuggestions.suggested({
            'navigationEndpoint': _watch('id', 'MUSIC_VIDEO_TYPE_ATV'),
            'flexColumns': 'garbled',
          }),
          isNull);
    });

    test('asked of YouTube Music: one request for both', () async {
      final ms = MusicServices();
      var requests = 0;
      ms.dio.interceptors
          .add(InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        expect(options.path, contains('music/get_search_suggestions'));
        expect(options.data['input'], 'radio');
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: _response));
      }));
      final s = await ms.getSearchSuggestions('radio');
      expect(s.queries, ['radiohead', 'radiohead creep']);
      expect(s.items, hasLength(5));
      expect(requests, 1);
      // The searches alone, as before.
      expect(await ms.getSearchSuggestion('radio'),
          ['radiohead', 'radiohead creep']);
    });
  });

  group('the search page as you type', () {
    late FakeMusicServices music;
    late _FakePlayer player;

    final artist = Artist(
        name: 'Radiohead',
        browseId: _radiohead,
        subscribers: '10.5M subscribers',
        thumbnailUrl: '');
    const song = MediaItem(
        id: 'XFkzRNyygfk',
        title: 'Creep',
        artist: 'Radiohead',
        extras: {'resultType': 'song'});

    setUp(() async {
      await Hive.openBox('searchQuery', bytes: Uint8List(0));
      await Hive.openBox('AppPrefs', bytes: Uint8List(0));
      SearchRecents.reload();
      music = Get.put<MusicServices>(FakeMusicServices()) as FakeMusicServices;
      music.suggestedItems = [artist, song];
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    Widget app() => MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Navigator(
            key: Get.nestedKey(ScreenNavigationSetup.id),
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => switch (settings.name) {
                ScreenNavigationSetup.artistScreen => Scaffold(
                    body: Text(
                        'artist: ${((settings.arguments as List)[1] as Artist).name}')),
                _ => const SearchScreen(),
              },
            ),
          ),
        );

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    testWidgets('the searches, then what YouTube Music would open',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await type(tester, 'radio');

      final c = Get.find<SearchScreenController>();
      expect(c.suggestedItems, [artist, song]);
      expect(find.text('Radiohead'), findsOneWidget);
      expect(find.text('artist'), findsOneWidget);
      expect(find.text('Creep'), findsOneWidget);
      expect(find.text('songKind · Radiohead'), findsOneWidget);
      // Below the searches.
      expect(tester.getTopLeft(find.byType(RichText).first).dy,
          lessThan(tester.getTopLeft(find.text('Radiohead')).dy));
      // Nothing to forget: the field's clear button is the only one.
      expect(find.byTooltip('clear'), findsOneWidget);

      // Played from there, and kept as a recent search.
      await tester.tap(find.text('Creep'));
      await tester.pump();
      expect(player.played, ['search: Creep']);
      expect(SearchRecents.items.first.item, isA<MediaItem>());

      // Opened from there.
      await tester.tap(find.text('Radiohead'));
      await tester.pumpAndSettle();
      expect(find.text('artist: Radiohead'), findsOneWidget);
    });

    testWidgets('explicit content off: explicit songs left out',
        (tester) async {
      ExplicitContent.allowed.value = false;
      addTearDown(() => ExplicitContent.allowed.value = true);
      music.suggestedItems = [
        artist,
        const MediaItem(
            id: 'explicit', title: 'Paranoid', extras: {'isExplicit': true}),
        song,
      ];
      await tester.pumpWidget(app());
      await tester.pump();
      await type(tester, 'radio');
      expect(find.text('Radiohead'), findsOneWidget);
      expect(find.text('Creep'), findsOneWidget);
      expect(find.text('Paranoid'), findsNothing);
    });

    testWidgets('gone with what was typed', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await type(tester, 'radio');
      expect(find.text('Creep'), findsOneWidget);

      await type(tester, '');
      final c = Get.find<SearchScreenController>();
      expect(c.suggestedItems, isEmpty);
      expect(find.text('Creep'), findsNothing);

      await type(tester, 'radio');
      expect(find.text('Creep'), findsOneWidget);
      c.reset();
      await tester.pump();
      expect(c.suggestedItems, isEmpty);
      expect(find.text('Creep'), findsNothing);
    });
  });
}
