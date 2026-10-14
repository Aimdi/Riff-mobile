import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/yt_library_parser.dart';
import 'package:harmonymusic/services/yt_playlists_import.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/yt_playlists_import_tile.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
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

/// As the JSON YouTube sends (maps and lists of dynamic).
Map<String, dynamic> _json(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// The first page: a header, then the grid in an item section, with the
/// New playlist card first and a token for the next page.
Map<String, dynamic> _firstPage({bool inItemSection = true}) {
  final grid = {
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
  };
  return _json({
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
                          'contents': [grid]
                        }
                      }
                    else
                      grid,
                  ]
                }
              }
            }
          }
        ]
      }
    }
  });
}

final _secondPage = _json({
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

Playlist _playlist(String title, String id) =>
    Playlist(title: title, playlistId: id, thumbnailUrl: '', description: '');

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final ytConnected = true.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('reading Library › Playlists', () {
    test('the first page, its playlists and the next page', () {
      for (final inItemSection in [true, false]) {
        final page =
            libraryGridFirstPage(_firstPage(inItemSection: inItemSection));
        expect(page.next, 'TOKEN2');
        final playlists = parseLibraryPlaylists(page.items);
        // Not the New playlist card.
        expect(playlists.map((p) => p.playlistId),
            ['VLLM', 'VLPLroadtrip', 'VLPLsavedmix', 'VLSE']);
        expect(playlists[1].title, 'Road trip');
        expect(playlists[1].thumbnailUrl, contains('VLPLroadtrip'));
        expect(playlists[1].isCloudPlaylist, isTrue);
      }
      final empty = libraryGridFirstPage(_json({'contents': {}}));
      expect(empty.items, isEmpty);
      expect(empty.next, isNull);
    });

    test('the pages after it, in either form', () {
      final last = libraryGridNextPage(_secondPage);
      expect(parseLibraryPlaylists(last.items).single.playlistId, 'VLPLgym');
      expect(last.next, isNull);

      final appended = libraryGridNextPage(_appendedPage);
      expect(parseLibraryPlaylists(appended.items).single.title, 'Gym');
      expect(appended.next, 'TOKEN3');

      expect(libraryGridNextPage(_json({})).items, isEmpty);
    });

    test("the account's library, page after page", () async {
      final music = MusicServices();
      expect(await music.getLibraryPlaylists(), isEmpty, reason: 'no account');

      await SecureCredentials.set('ytAuthCookie', 'SAPISID=abc; HSID=def');
      final asked = <RequestOptions>[];
      var status = 200;
      music.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        asked.add(o);
        final more = o.uri.queryParameters['ctoken'] == 'TOKEN2';
        h.resolve(Response(
            requestOptions: o,
            statusCode: status,
            data: status != 200
                ? {'error': {}}
                : more
                    ? _secondPage
                    : _firstPage()));
      }));
      final playlists = await music.getLibraryPlaylists();
      expect(playlists.map((p) => p.playlistId),
          ['VLLM', 'VLPLroadtrip', 'VLPLsavedmix', 'VLSE', 'VLPLgym']);
      expect(asked, hasLength(2));
      expect((asked.first.data as Map)['browseId'], 'FEmusic_liked_playlists');
      expect(asked.first.headers['authorization'], startsWith('SAPISIDHASH '));
      expect(asked.last.uri.queryParameters['continuation'], 'TOKEN2');

      expect(await music.getLibraryPlaylists(limit: 2), hasLength(2));

      // Signed out there: a failure, not an empty library.
      status = 401;
      await expectLater(music.getLibraryPlaylists(), throwsA(anything));
      SecureCredentials.resetForTest();
    });
  });

  group('into the Library', () {
    late List<Playlist> library;

    setUp(() async {
      await Hive.openBox(YtPlaylistsImport.libraryBox, bytes: Uint8List(0));
      library = [
        _playlist('Liked Music', 'VLLM'),
        _playlist('Road trip', 'VLPLroadtrip'),
        _playlist('Saved mix', 'VLPLsavedmix'),
        _playlist('Gym', 'VLPLgym'),
        _playlist('Episodes for Later', 'VLSE'),
      ];
      YtPlaylistsImport.connected = () => true;
      YtPlaylistsImport.fetch = () async => library;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    test('the playlists not there yet; Liked music and episodes stay out',
        () async {
      final box = Hive.box(YtPlaylistsImport.libraryBox);
      // Saved in Riff before, under either form of its id.
      await box.put(
          'PLsavedmix', _playlist('Saved mix', 'PLsavedmix').toJson());
      await box.put('VLPLgym', _playlist('Gym', 'VLPLgym').toJson());

      expect(await YtPlaylistsImport.importPlaylists(), 1);
      expect(
          box.keys, unorderedEquals(['PLsavedmix', 'VLPLgym', 'VLPLroadtrip']));
      final road = Playlist.fromJson(box.get('VLPLroadtrip'));
      expect(road.title, 'Road trip');
      expect(road.isCloudPlaylist, isTrue);

      expect(await YtPlaylistsImport.importPlaylists(), 0);
      expect(YtPlaylistsImport.importing.value, isFalse);
    });

    test("without an account, or YouTube out of reach: nothing", () async {
      YtPlaylistsImport.fetch = () => throw Exception('offline');
      expect(await YtPlaylistsImport.importPlaylists(), isNull);
      expect(YtPlaylistsImport.importing.value, isFalse);
      YtPlaylistsImport.connected = () => false;
      expect(await YtPlaylistsImport.importPlaylists(), isNull);
      expect(Hive.box(YtPlaylistsImport.libraryBox).isEmpty, isTrue);
    });

    testWidgets('Settings: a tap brings them in and says how many',
        (tester) async {
      final settings =
          Get.put<SettingsScreenController>(_FakeSettings()) as _FakeSettings;
      await tester.pumpWidget(GetMaterialApp(
        theme: RiffTheme.dark(const Color(0xFF1DB954)),
        home: const Scaffold(body: YtPlaylistsImportTile()),
      ));
      expect(find.text('ytPlaylistsImport'), findsOneWidget);
      settings.ytConnected.value = false;
      await tester.pump();
      expect(find.text('ytPlaylistsImport'), findsNothing,
          reason: 'no account');

      settings.ytConnected.value = true;
      await tester.pump();
      await tester.tap(find.text('ytPlaylistsImport'));
      await tester.pump();
      await tester.pump();
      expect(Hive.box(YtPlaylistsImport.libraryBox).length, 3);
      expect(find.text('ytPlaylistsImported'), findsOneWidget);
      await tester.pumpAndSettle();

      // Again: they're all there (its snackbar in place of the first).
      await tester.tap(find.text('ytPlaylistsImport'));
      await tester.pumpAndSettle();
      expect(find.text('ytPlaylistsUpToDate'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
