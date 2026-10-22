import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/services/album_versions.dart';
import 'package:harmonymusic/services/downloader.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Album/album_screen.dart';
import 'package:harmonymusic/ui/screens/Album/album_screen_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:hive/hive.dart';

import 'fakes/fake_music_services.dart';

Map<String, dynamic> _track(String id) => {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': id},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Track $id'}
                ]
              }
            }
          }
        ],
      }
    };

/// An album on a carousel, as YouTube Music's pages show them.
Map<String, dynamic> _twoRow(String title, String browseId,
        {String kind = 'Album', bool broken = false}) =>
    {
      'musicTwoRowItemRenderer': {
        'title': {
          'runs': [
            {
              'text': title,
              'navigationEndpoint': {
                'browseEndpoint': {'browseId': browseId}
              },
            }
          ]
        },
        if (!broken)
          'subtitle': {
            'runs': [
              {'text': kind},
              {'text': ' • '},
              {'text': '2009'},
            ]
          },
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://lh3.googleusercontent.com/$browseId'}
              ]
            }
          }
        },
      }
    };

Map<String, dynamic> _carousel(List items, {String title = 'Other versions'}) =>
    {
      'musicCarouselShelfRenderer': {
        'header': {
          'musicCarouselShelfBasicHeaderRenderer': {
            'title': {
              'runs': [
                {'text': title}
              ]
            }
          }
        },
        'contents': items,
      }
    };

/// YouTube Music's page for the album MPREb_x: its header, its tracks,
/// then what [below] holds.
Map<String, dynamic> _albumPage(List below) => {
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicResponsiveHeaderRenderer': {
                          'title': {
                            'runs': [
                              {'text': 'In Rainbows'}
                            ]
                          },
                          'subtitle': {
                            'runs': [
                              {'text': 'Album'},
                              {'text': ' • '},
                              {'text': '2007'},
                            ]
                          },
                          'secondSubtitle': {
                            'runs': [
                              {'text': '2 songs'},
                              {'text': ' • '},
                              {'text': '7 minutes'},
                            ]
                          },
                        }
                      }
                    ]
                  }
                }
              }
            }
          ],
          'secondaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicShelfRenderer': {
                    'contents': [_track('t1'), _track('t2')]
                  }
                },
                ...below,
              ]
            }
          },
        }
      }
    };

MusicServices _service(Object? answer) {
  final ms = MusicServices();
  ms.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: answer));
  }));
  return ms;
}

final _deluxe = Album(
    title: 'In Rainbows (Deluxe)',
    browseId: 'MPREb_deluxe',
    thumbnailUrl: '',
    artists: const [
      {'name': 'Radiohead', 'id': 'UC1'}
    ]);
final _kidA = Album(
    title: 'Kid A',
    browseId: 'MPREb_kida',
    thumbnailUrl: '',
    artists: const [
      {'name': 'Radiohead', 'id': 'UC1'}
    ]);

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final playerPanelMinHeight = 0.0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDownloader extends GetxService implements Downloader {
  @override
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  @override
  final currentPlaylistId = ''.obs;
  @override
  final playlistDownloadingProgress = 0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final slidableActionEnabled = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In Rainbows, its deluxe edition, and Radiohead's page with both and
/// Kid A.
class _Music extends FakeMusicServices {
  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int? limit,
      bool related = false,
      int suggestionsLimit = 0}) async {
    playlistCalls++;
    return {
      'title': 'In Rainbows',
      'artists': const [
        {'name': 'Radiohead', 'id': 'UC1'}
      ],
      'tracks': const [
        MediaItem(id: 'aaaaaaaaaaa', title: '15 Step'),
        MediaItem(id: 'bbbbbbbbbbb', title: 'Bodysnatchers'),
      ],
      'otherVersions': AlbumVersions('Other versions', [_deluxe]),
    };
  }

  @override
  Future<Map<String, dynamic>> getArtist(String channelId) async => {
        'name': 'Radiohead',
        'Albums': {
          'content': [_deluxe, _kidA]
        },
      };
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// An album's other versions (a deluxe edition, a remaster) under its
/// tracks, as YouTube Music's and Apple Music's album pages list them.
void main() {
  group('read from the album page', () {
    test('its carousel of albums, by its own title, the album left out', () {
      final v = AlbumVersions.fromAlbumPage(
          _albumPage([
            _carousel([
              _twoRow('In Rainbows (Deluxe)', 'MPREb_deluxe'),
              _twoRow('In Rainbows', 'MPREb_x'),
              _twoRow('In Rainbows (Deluxe)', 'MPREb_deluxe'),
              _twoRow('A playlist', 'VLPLx', kind: 'Playlist'),
              _twoRow('Unreadable', 'MPREb_broken', broken: true),
              _twoRow('In Rainbows (Disk 2)', 'MPREb_disk2', kind: 'EP'),
            ], title: 'Autres versions'),
          ]),
          currentBrowseId: 'MPREb_x')!;
      expect(v.title, 'Autres versions');
      expect(v.albums.map((a) => a.browseId), ['MPREb_deluxe', 'MPREb_disk2']);
      expect(v.albums.first.title, 'In Rainbows (Deluxe)');
    });

    test('none, or nothing readable: nothing', () {
      expect(
          AlbumVersions.fromAlbumPage(_albumPage([]),
              currentBrowseId: 'MPREb_x'),
          isNull);
      expect(
          AlbumVersions.fromAlbumPage(
              _albumPage([
                _carousel([
                  _twoRow('Broken', 'MPREb_b', broken: true),
                  'garbage',
                ]),
                {'musicCarouselShelfRenderer': 'garbage'},
              ]),
              currentBrowseId: 'MPREb_x'),
          isNull);
      expect(AlbumVersions.fromAlbumPage(null, currentBrowseId: 'x'), isNull);
    });

    test('kept with the album; an odd carousel never costs its tracks',
        () async {
      final album = await _service(_albumPage([
        _carousel([_twoRow('In Rainbows (Deluxe)', 'MPREb_deluxe')]),
      ])).getPlaylistOrAlbumSongs(albumId: 'MPREb_x');
      expect((album['otherVersions'] as AlbumVersions).albums.single.browseId,
          'MPREb_deluxe');
      expect((album['tracks'] as List).cast<MediaItem>().map((t) => t.id),
          ['t1', 't2']);

      final odd = await _service(_albumPage([
        {
          'musicCarouselShelfRenderer': {
            'contents': [
              {'musicTwoRowItemRenderer': 'garbage'}
            ]
          }
        },
      ])).getPlaylistOrAlbumSongs(albumId: 'MPREb_x');
      expect(odd.containsKey('otherVersions'), isFalse);
      expect((odd['tracks'] as List), hasLength(2));
    });
  });

  group('the album page', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('album_versions');
      Hive.init(tmp.path);
      await Hive.openBox('SongDownloads');
      Get.put<MusicServices>(_Music());
    });

    tearDown(() async {
      Get.reset();
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    testWidgets('under the tracks, then More by without them', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Get.put<PlayerController>(_FakePlayer());
      Get.put<Downloader>(_FakeDownloader());
      Get.put<SettingsScreenController>(_FakeSettings());
      final tag = const Key('MPREb_x').hashCode.toString();
      await tester.runAsync(() async {
        await tester.pumpWidget(GetMaterialApp(
          home: Builder(builder: (_) {
            Get.routing.args = (null, 'MPREb_x');
            return const AlbumScreen(key: Key('MPREb_x'));
          }),
        ));
        await _until(() {
          final c = Get.find<AlbumScreenController>(tag: tag);
          return c.isContentFetched.isTrue && c.moreByArtist.isNotEmpty;
        });
      });
      await tester.pumpAndSettle();

      final c = Get.find<AlbumScreenController>(tag: tag);
      expect(c.otherVersions.map((a) => a.browseId), ['MPREb_deluxe']);
      // Headed as the page calls them (section titles in sentence case).
      expect(find.text('Other versions'), findsOneWidget);
      expect(find.text('In Rainbows (Deluxe)'), findsOneWidget);
      // Below the tracks, above More by, which leaves the deluxe out.
      expect(tester.getTopLeft(find.text('Bodysnatchers')).dy,
          lessThan(tester.getTopLeft(find.text('Other versions')).dy));
      expect(find.text('moreByArtist'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Other versions')).dy,
          lessThan(tester.getTopLeft(find.text('moreByArtist')).dy));
      expect(find.text('Kid A'), findsOneWidget);
      expect(c.moreByArtistShown.map((a) => a.browseId), ['MPREb_kida']);
    });
  });
}
