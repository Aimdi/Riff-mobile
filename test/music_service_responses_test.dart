import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/music_service.dart';

/// [MusicServices] answering from [answer] instead of the network: the
/// endpoint path ("browse", "next", …) and request body go in, the decoded
/// JSON comes out.
MusicServices _service(
    Object? Function(String endpoint, Map<String, dynamic> body) answer) {
  final ms = MusicServices();
  ms.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final endpoint = options.uri.pathSegments.skip(2).join('/');
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: answer(endpoint, Map<String, dynamic>.from(options.data as Map)),
    ));
  }));
  return ms;
}

Map<String, dynamic> _albumTrack(String id) => {
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

void main() {
  test('search suggestions without a query are dropped, not "null"', () async {
    final ms = _service((endpoint, body) => {
          'contents': [
            {
              'searchSuggestionsSectionRenderer': {
                'contents': [
                  {
                    'searchSuggestionRenderer': {
                      'navigationEndpoint': {
                        'searchEndpoint': {'query': 'daft punk'}
                      }
                    }
                  },
                  {
                    'historySuggestionRenderer': {'text': 'old'}
                  },
                ]
              }
            }
          ]
        });
    expect(await ms.getSearchSuggestion('daft'), ['daft punk']);
  });

  test('a short video id reaches the request instead of a RangeError',
      () async {
    String? sentVideoId;
    final ms = _service((endpoint, body) {
      sentVideoId = body['videoId'] as String?;
      return <String, dynamic>{};
    });
    final res = await ms.getWatchPlaylist(videoId: 'abc');
    expect(sentVideoId, 'abc');
    expect(res['tracks'], isEmpty);

    await ms.getWatchPlaylist(videoId: 'MPEDxyz');
    expect(sentVideoId, 'xyz');
  });

  test('an album with an odd "other versions" carousel still loads', () async {
    final ms = _service((endpoint, body) => {
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
                                  {'text': 'Album'}
                                ]
                              },
                              'subtitle': {
                                'runs': [
                                  {'text': 'Album'},
                                  {'text': ' • '},
                                  {'text': '2024'},
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
                        'contents': [_albumTrack('t1'), _albumTrack('t2')]
                      }
                    }
                  ]
                }
              },
            },
            // The old code read contents[0] of this carousel unconditionally.
            'singleColumnBrowseResultsRenderer': {
              'tabs': [
                {
                  'tabRenderer': {
                    'content': {
                      'sectionListRenderer': {
                        'contents': [
                          {},
                          {
                            'musicCarouselShelfRenderer': {'contents': []}
                          }
                        ]
                      }
                    }
                  }
                }
              ]
            },
          }
        });
    final album = await ms.getPlaylistOrAlbumSongs(albumId: 'MPREb_x');
    expect(album['title'], 'Album');
    expect((album['tracks'] as List).cast<MediaItem>().map((t) => t.id),
        ['t1', 't2']);
  });

  test('an album page without a track shelf is a FormatException', () async {
    final ms = _service((endpoint, body) => {
          'header': {
            'musicDetailHeaderRenderer': {
              'title': {
                'runs': [
                  {'text': 'Album'}
                ]
              },
              'subtitle': {
                'runs': [
                  {'text': 'Album'},
                  {'text': ' • '},
                  {'text': 'X'},
                ]
              },
              'secondSubtitle': {
                'runs': [
                  {'text': '1 song'}
                ]
              },
            }
          }
        });
    expect(ms.getPlaylistOrAlbumSongs(albumId: 'MPREb_y'),
        throwsA(isA<FormatException>()));
  });
}
