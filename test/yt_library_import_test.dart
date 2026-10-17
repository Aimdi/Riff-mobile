import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/discovery/discovery_service.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/yt_library_import.dart';
import 'package:harmonymusic/services/yt_library_parser.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/yt_library_import_tile.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

/// A playlist's card in YouTube Music's Library › Playlists grid.
Map<String, dynamic> _card(String title, String browseId) => {
      'musicTwoRowItemRenderer': {
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://i.example/$browseId.jpg', 'width': 226}
              ]
            }
          }
        },
        'title': {
          'runs': [
            {
              'text': title,
              'navigationEndpoint': {
                'browseEndpoint': {'browseId': browseId}
              }
            }
          ]
        },
        'subtitle': {
          'runs': [
            {'text': 'Playlist'},
            {'text': ' • '},
            {'text': '12 songs'}
          ]
        },
      }
    };

/// An artist's row in the account's subscriptions shelf.
Map<String, dynamic> _row(String name, String browseId) => {
      'musicResponsiveListItemRenderer': {
        'thumbnail': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://i.example/$browseId.jpg', 'width': 120}
              ]
            }
          }
        },
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': name}
                ]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': '1.2M subscribers'}
                ]
              }
            }
          },
        ],
        'navigationEndpoint': {
          'browseEndpoint': {'browseId': browseId}
        },
      }
    };

/// An album's card in Library › Albums: "Album • artist • year".
Map<String, dynamic> _albumCard(String title, String browseId) => {
      'musicTwoRowItemRenderer': {
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://i.example/$browseId.jpg', 'width': 226}
              ]
            }
          }
        },
        'title': {
          'runs': [
            {
              'text': title,
              'navigationEndpoint': {
                'browseEndpoint': {'browseId': browseId}
              }
            }
          ]
        },
        'subtitle': {
          'runs': [
            {'text': 'Album'},
            {'text': ' • '},
            {
              'text': 'The Band',
              'navigationEndpoint': {
                'browseEndpoint': {'browseId': 'UCtheband'}
              }
            },
            {'text': ' • '},
            {'text': '2020'},
          ]
        },
      }
    };

/// As the JSON YouTube sends (maps and lists of dynamic).
Map<String, dynamic> _json(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// A library page: a header, then [list] in an item section (or not).
Map<String, dynamic> _libraryPage(Map<String, dynamic> list,
        {bool inItemSection = true}) =>
    _json({
      'contents': {
        'singleColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {'musicSideAlignedItemRenderer': {}},
                      if (inItemSection)
                        {
                          'itemSectionRenderer': {
                            'contents': [list]
                          }
                        }
                      else
                        list,
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    });

/// Library › Playlists: the New playlist card first, then the playlists,
/// and a token for the next page.
Map<String, dynamic> _playlistsPage({bool inItemSection = true}) =>
    _libraryPage({
      'gridRenderer': {
        'items': [
          {
            'musicTwoRowItemRenderer': {
              'title': {
                'runs': [
                  {'text': 'New playlist'}
                ]
              },
              'navigationEndpoint': {'createPlaylistServiceEndpoint': {}},
            }
          },
          _card('Liked Music', 'VLLM'),
          _card('Road trip', 'VLPLroadtrip'),
          _card('Saved mix', 'VLPLsavedmix'),
          _card('Episodes for Later', 'VLSE'),
        ],
        'continuations': [
          {
            'nextContinuationData': {'continuation': 'TOKEN2'}
          }
        ],
      }
    }, inItemSection: inItemSection);

final _playlistsPage2 = _json({
  'continuationContents': {
    'gridContinuation': {
      'items': [_card('Gym', 'VLPLgym')]
    }
  }
});

final _appendedPage = _json({
  'onResponseReceivedActions': [
    {
      'appendContinuationItemsAction': {
        'continuationItems': [
          _card('Gym', 'VLPLgym'),
          {
            'continuationItemRenderer': {
              'continuationEndpoint': {
                'continuationCommand': {'token': 'TOKEN3'}
              }
            }
          }
        ]
      }
    }
  ]
});

/// Library › Albums: two albums and a card that isn't one.
final _albumsPage = _libraryPage({
  'gridRenderer': {
    'items': [
      _albumCard('First Light', 'MPREfirstlight'),
      _card('A playlist', 'VLPLnotalbum'),
      _albumCard('Second Wind', 'MPREsecondwind'),
    ],
  }
});

/// Library › Podcasts: the New episodes card first, then two shows.
final _podcastsPage = _libraryPage({
  'gridRenderer': {
    'items': [
      _card('New Episodes', 'VLRDPN'),
      _podcastCard('Show One', 'MPSPPLshowone'),
      _podcastCard('Show Two', 'MPSPPLshowtwo'),
    ],
  }
});

/// A show's card in Library › Podcasts: its channel under the title.
Map<String, dynamic> _podcastCard(String title, String browseId) {
  final card = _card(title, browseId);
  card['musicTwoRowItemRenderer']['subtitle'] = {
    'runs': [
      {'text': 'The Channel'}
    ]
  };
  return card;
}

/// The subscriptions shelf: two artists and a row that isn't one.
final _artistsPage = _libraryPage({
  'musicShelfRenderer': {
    'contents': [
      _row('The Band', 'UCtheband'),
      _row('Some Album', 'MPREalbum'),
      _row('Solo Singer', 'UCsolosinger'),
    ],
    'continuations': [
      {
        'nextContinuationData': {'continuation': 'ART2'}
      }
    ],
  }
});

final _artistsPage2 = _json({
  'continuationContents': {
    'musicShelfContinuation': {
      'contents': [_row('Late Bloomer', 'UClatebloomer')]
    }
  }
});

Playlist _playlist(String title, String id) =>
    Playlist(title: title, playlistId: id, thumbnailUrl: '', description: '');

Album _album(String title, String id) => Album(
    title: title,
    browseId: id,
    artists: [
      {'name': 'The Band', 'id': 'UCtheband'}
    ],
    thumbnailUrl: 'https://i.example/$id.jpg');

Artist _artist(String name, String id) =>
    Artist(name: name, browseId: id, thumbnailUrl: 'https://i.example/$id.jpg');

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final ytConnected = true.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo implements DiscoveryRepository {
  final followed = <String>[];

  @override
  Future<void> followArtist(String channelId,
          {required String name, String? thumbnailUrl}) async =>
      followed.add('$channelId $name');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDiscovery extends GetxService implements DiscoveryService {
  @override
  final _FakeRepo repo = _FakeRepo();
  final liked = <String>[];

  @override
  Future<void> onFollow(String artistName, {required bool follow}) async =>
      liked.add('$artistName $follow');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('reading the library', () {
    test('Library › Playlists: the first page, its playlists, the next', () {
      for (final inItemSection in [true, false]) {
        final page =
            libraryFirstPage(_playlistsPage(inItemSection: inItemSection));
        expect(page.next, 'TOKEN2');
        final playlists = parseLibraryPlaylists(page.items);
        // Not the New playlist card.
        expect(playlists.map((p) => p.playlistId),
            ['VLLM', 'VLPLroadtrip', 'VLPLsavedmix', 'VLSE']);
        expect(playlists[1].title, 'Road trip');
        expect(playlists[1].thumbnailUrl, contains('VLPLroadtrip'));
        expect(playlists[1].isCloudPlaylist, isTrue);
      }
      final empty = libraryFirstPage(_json({'contents': {}}));
      expect(empty.items, isEmpty);
      expect(empty.next, isNull);
    });

    test('the pages after it, in either form', () {
      final last = libraryNextPage(_playlistsPage2);
      expect(parseLibraryPlaylists(last.items).single.playlistId, 'VLPLgym');
      expect(last.next, isNull);

      final appended = libraryNextPage(_appendedPage);
      expect(parseLibraryPlaylists(appended.items).single.title, 'Gym');
      expect(appended.next, 'TOKEN3');

      expect(libraryNextPage(_json({})).items, isEmpty);
    });

    test('the albums you saved: artist and year after their type', () {
      final page = libraryFirstPage(_albumsPage);
      expect(page.next, isNull);
      final albums = parseLibraryAlbums(page.items);
      // Not the playlist's card.
      expect(
          albums.map((a) => a.browseId), ['MPREfirstlight', 'MPREsecondwind']);
      final first = albums.first;
      expect(first.title, 'First Light');
      expect(first.artists, [
        {'name': 'The Band', 'id': 'UCtheband'}
      ]);
      expect(first.year, '2020');
      expect(first.description, 'Album • The Band • 2020');
      expect(first.thumbnailUrl, contains('MPREfirstlight'));
    });

    test('the podcasts you follow, not the New episodes card', () {
      final podcasts =
          parseLibraryPodcasts(libraryFirstPage(_podcastsPage).items);
      expect(podcasts.map((p) => p.playlistId),
          ['MPSPPLshowone', 'MPSPPLshowtwo']);
      expect(podcasts.first.title, 'Show One');
      expect(podcasts.first.kind, 'podcast');
      expect(podcasts.first.description, 'The Channel');
      expect(podcasts.first.thumbnailUrl, contains('MPSPPLshowone'));
    });

    test('the artists you subscribe to, page after page', () {
      final page = libraryFirstPage(_artistsPage);
      expect(page.next, 'ART2');
      final artists = parseLibraryArtists(page.items);
      // Not the album's row.
      expect(artists.map((a) => a.browseId), ['UCtheband', 'UCsolosinger']);
      expect(artists.first.name, 'The Band');
      expect(artists.first.subscribers, '1.2M subscribers');
      expect(artists.first.thumbnailUrl, contains('UCtheband'));

      final next = libraryNextPage(_artistsPage2);
      expect(parseLibraryArtists(next.items).single.name, 'Late Bloomer');
      expect(next.next, isNull);
    });

    test("the account's library, page after page", () async {
      final music = MusicServices();
      expect(await music.getLibraryPlaylists(), isEmpty, reason: 'no account');
      expect(await music.getLibrarySubscriptions(), isEmpty);

      await SecureCredentials.set('ytAuthCookie', 'SAPISID=abc; HSID=def');
      final asked = <RequestOptions>[];
      var status = 200;
      music.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        asked.add(o);
        final browseId = (o.data as Map)['browseId'];
        final token = o.uri.queryParameters['ctoken'];
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: status != 200
                ? {'error': {}}
                : switch ((browseId, token)) {
                    ('FEmusic_liked_playlists', 'TOKEN2') => _playlistsPage2,
                    ('FEmusic_liked_playlists', _) => _playlistsPage(),
                    ('FEmusic_liked_albums', _) => _albumsPage,
                    ('FEmusic_library_non_music_audio_list', _) =>
                      _podcastsPage,
                    (_, 'ART2') => _artistsPage2,
                    _ => _artistsPage,
                  }));
      }));
      final playlists = await music.getLibraryPlaylists();
      expect(playlists.map((p) => p.playlistId),
          ['VLLM', 'VLPLroadtrip', 'VLPLsavedmix', 'VLSE', 'VLPLgym']);
      expect(asked, hasLength(2));
      expect(asked.first.headers['authorization'], startsWith('SAPISIDHASH '));
      expect(asked.last.uri.queryParameters['continuation'], 'TOKEN2');
      expect(await music.getLibraryPlaylists(limit: 2), hasLength(2));

      expect((await music.getLibraryAlbums()).map((a) => a.title),
          ['First Light', 'Second Wind']);
      expect((await music.getLibraryPodcasts()).map((p) => p.title),
          ['Show One', 'Show Two']);

      asked.clear();
      final artists = await music.getLibrarySubscriptions();
      expect(artists.map((a) => a.name),
          ['The Band', 'Solo Singer', 'Late Bloomer']);
      expect((asked.first.data as Map)['browseId'],
          'FEmusic_library_corpus_artists');

      // Signed out there: a failure, not an empty library.
      status = 401;
      await expectLater(music.getLibraryPlaylists(), throwsA(anything));
      await expectLater(music.getLibrarySubscriptions(), throwsA(anything));
      await expectLater(music.getLibraryAlbums(), throwsA(anything));
      await expectLater(music.getLibraryPodcasts(), throwsA(anything));
      SecureCredentials.resetForTest();
    });
  });

  group('into the Library', () {
    late List<Playlist> playlists;
    late List<Album> albums;
    late List<Artist> artists;
    late List<Playlist> podcasts;

    setUp(() async {
      await Hive.openBox(YtLibraryImport.playlistsBox, bytes: Uint8List(0));
      await Hive.openBox(YtLibraryImport.albumsBox, bytes: Uint8List(0));
      await Hive.openBox(YtLibraryImport.artistsBox, bytes: Uint8List(0));
      await Hive.openBox(YtLibraryImport.podcastsBox, bytes: Uint8List(0));
      playlists = [
        _playlist('Liked Music', 'VLLM'),
        _playlist('Road trip', 'VLPLroadtrip'),
        _playlist('Saved mix', 'VLPLsavedmix'),
        _playlist('Gym', 'VLPLgym'),
        _playlist('Episodes for Later', 'VLSE'),
      ];
      albums = [
        _album('First Light', 'MPREfirstlight'),
        _album('Second Wind', 'MPREsecondwind'),
      ];
      artists = [
        _artist('The Band', 'UCtheband'),
        _artist('Solo Singer', 'UCsolosinger'),
      ];
      YtLibraryImport.connected = () => true;
      YtLibraryImport.fetchPlaylists = () async => playlists;
      YtLibraryImport.fetchAlbums = () async => albums;
      YtLibraryImport.fetchArtists = () async => artists;
      podcasts = [
        Playlist(
            title: 'Show One',
            playlistId: 'MPSPPLshowone',
            thumbnailUrl: '',
            description: 'The Channel',
            kind: 'podcast'),
        Playlist(
            title: 'Show Two',
            playlistId: 'MPSPPLshowtwo',
            thumbnailUrl: '',
            kind: 'podcast'),
      ];
      YtLibraryImport.fetchPodcasts = () async => podcasts;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    test(
        'the playlists and artists not there yet; Liked music and '
        'episodes stay out', () async {
      final discovery =
          Get.put<DiscoveryService>(_FakeDiscovery()) as _FakeDiscovery;
      final playlistsBox = Hive.box(YtLibraryImport.playlistsBox);
      final artistsBox = Hive.box(YtLibraryImport.artistsBox);
      // Saved in Riff before, a playlist under either form of its id.
      await playlistsBox.put(
          'PLsavedmix', _playlist('Saved mix', 'PLsavedmix').toJson());
      await playlistsBox.put('VLPLgym', _playlist('Gym', 'VLPLgym').toJson());
      await artistsBox.put(
          'UCsolosinger', _artist('Solo Singer', 'UCsolosinger').toJson());
      // Followed in Riff before, under its playlist id.
      final podcastsBox = Hive.box(YtLibraryImport.podcastsBox);
      await podcastsBox.put('PLshowtwo', {'title': 'Show Two'});
      final albumsBox = Hive.box(YtLibraryImport.albumsBox);
      await albumsBox.put(
          'MPREsecondwind', _album('Second Wind', 'MPREsecondwind').toJson());

      final came = await YtLibraryImport.importLibrary();
      expect(came, (playlists: 1, albums: 1, artists: 1, podcasts: 1));
      expect(podcastsBox.keys, unorderedEquals(['PLshowtwo', 'MPSPPLshowone']));
      final show = podcastsBox.get('MPSPPLshowone') as Map;
      expect(show['title'], 'Show One');
      expect(show['kind'], 'podcast');
      expect(show['description'], 'The Channel');
      expect(show['addedAt'], isA<int>());
      expect(albumsBox.keys,
          unorderedEquals(['MPREfirstlight', 'MPREsecondwind']));
      final light = Album.fromJson(albumsBox.get('MPREfirstlight'));
      expect(light.title, 'First Light');
      expect(light.artists?.single['name'], 'The Band');
      expect(playlistsBox.keys,
          unorderedEquals(['PLsavedmix', 'VLPLgym', 'VLPLroadtrip']));
      final road = Playlist.fromJson(playlistsBox.get('VLPLroadtrip'));
      expect(road.title, 'Road trip');
      expect(road.isCloudPlaylist, isTrue);
      final band = Artist.fromJson(artistsBox.get('UCtheband'));
      expect(band.name, 'The Band');
      // Followed as following one in Riff does: Release Radar, and liked.
      expect(discovery.repo.followed, ['UCtheband The Band']);
      expect(discovery.liked, ['The Band true']);

      expect(await YtLibraryImport.importLibrary(),
          (playlists: 0, albums: 0, artists: 0, podcasts: 0));
      expect(discovery.repo.followed, hasLength(1));
      expect(YtLibraryImport.importing.value, isFalse);
    });

    test('one part out of reach: the other still comes; no account: nothing',
        () async {
      YtLibraryImport.fetchPlaylists = () => throw Exception('offline');
      expect(await YtLibraryImport.importLibrary(),
          (playlists: null, albums: 2, artists: 2, podcasts: 2));
      expect(YtLibraryImport.importing.value, isFalse);
      YtLibraryImport.connected = () => false;
      expect(await YtLibraryImport.importLibrary(), isNull);
    });

    test('what the snackbar says', () {
      Get.addTranslations(Languages().keys);
      Get.locale = const Locale('en');
      expect(
          ytLibraryImportedText(
              (playlists: 3, albums: 2, artists: 1, podcasts: 4)),
          'Added from YouTube Music: 3 playlists, 2 albums, 1 artist, '
          '4 podcasts');
      expect(
          ytLibraryImportedText(
              (playlists: 1, albums: 0, artists: 0, podcasts: 0)),
          'Added from YouTube Music: 1 playlist');
      expect(
          ytLibraryImportedText(
              (playlists: null, albums: 1, artists: 5, podcasts: 1)),
          'Added from YouTube Music: 1 album, 5 artists, 1 podcast');
      expect(
          ytLibraryImportedText(
              (playlists: 0, albums: 0, artists: 0, podcasts: 0)),
          'Your Library already has your YouTube Music playlists, albums, '
          'artists and podcasts');
      expect(
          ytLibraryImportedText(
              (playlists: 0, albums: 0, artists: 0, podcasts: null)),
          "YouTube Music couldn't be reached. Try again later");
      Get.clearTranslations();
    });

    testWidgets('Settings: a tap brings them in and says what came',
        (tester) async {
      final settings =
          Get.put<SettingsScreenController>(_FakeSettings()) as _FakeSettings;
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: YtLibraryImportTile()),
      ));
      expect(find.text('ytLibraryImport'), findsOneWidget);
      settings.ytConnected.value = false;
      await tester.pump();
      expect(find.text('ytLibraryImport'), findsNothing, reason: 'no account');

      settings.ytConnected.value = true;
      await tester.pump();
      await tester.tap(find.text('ytLibraryImport'));
      await tester.pump();
      await tester.pump();
      expect(Hive.box(YtLibraryImport.playlistsBox).length, 3);
      expect(Hive.box(YtLibraryImport.albumsBox).length, 2);
      expect(Hive.box(YtLibraryImport.artistsBox).length, 2);
      expect(Hive.box(YtLibraryImport.podcastsBox).length, 2);
      // `.tr` gives the key in tests.
      expect(find.text('ytLibraryImported'), findsOneWidget);
      await tester.pumpAndSettle();

      // Again: it's all there (its snackbar in place of the first).
      await tester.tap(find.text('ytLibraryImport'));
      await tester.pumpAndSettle();
      expect(find.text('ytLibraryUpToDate'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
