import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/continuations.dart';
import 'package:harmonymusic/services/nav_parser.dart';
import 'package:harmonymusic/services/utils.dart';

Map<String, dynamic> _flex(String text, {Map<String, dynamic>? endpoint}) => {
      'musicResponsiveListItemFlexColumnRenderer': {
        'text': {
          'runs': [
            {'text': text, if (endpoint != null) 'navigationEndpoint': endpoint}
          ]
        }
      }
    };

/// A playlist row as YouTube Music sends it; [fixedText] is the duration
/// column's `text` object (simpleText or runs).
Map<String, dynamic> _playlistRow(String videoId,
        {Map<String, dynamic>? fixedText, bool withTitle = true}) =>
    {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': videoId},
        'flexColumns': [
          if (withTitle) _flex('Song $videoId'),
          if (withTitle) _flex('Artist'),
        ],
        if (fixedText != null)
          'fixedColumns': [
            {
              'musicResponsiveListItemFixedColumnRenderer': {'text': fixedText}
            }
          ],
      }
    };

void main() {
  group('parseDuration', () {
    test('reads m:ss and h:mm:ss as seconds', () {
      expect(parseDuration('3:45'), 225);
      expect(parseDuration('1:02:03'), 3723);
      expect(parseDuration('45'), 45);
      expect(parseDuration('0:07'), 7);
    });

    test('malformed text is null, not an exception', () {
      expect(parseDuration(null), isNull);
      expect(parseDuration('1:xx'), isNull);
      expect(parseDuration('1:2:3:4'), isNull);
      expect(parseDuration(''), isNull);
    });

    test('a podcast episode with a clock duration gets the right length', () {
      final episode = parseEpisodeItem({
        'onTap': {
          'watchEndpoint': {'videoId': 'ep1'}
        },
        'title': {
          'runs': [
            {'text': 'Episode'}
          ]
        },
        'playbackProgress': {
          'musicPlaybackProgressRenderer': {
            'durationText': {
              'runs': [
                {'text': '45:12'}
              ]
            }
          }
        },
      });
      // Used to be 12 * 3600 + 45 * 3540 seconds (over 56 hours).
      expect(episode!.duration, const Duration(minutes: 45, seconds: 12));
    });
  });

  group('getDotSeparatorIndex', () {
    test('is the run count when there is no separator', () {
      final runs = [
        {'text': 'Artist'},
        {'text': '1.2M views'},
      ];
      expect(getDotSeparatorIndex(runs), 2);
      expect(
          getDotSeparatorIndex([
            {'text': 'A'},
            {'text': ' • '},
            {'text': 'B'},
          ]),
          1);
    });

    test('parseVideo copes with subtitle runs without a separator', () {
      final video = parseVideo({
        'title': {
          'runs': [
            {'text': 'Clip'}
          ]
        },
        'navigationEndpoint': {
          'watchEndpoint': {'videoId': 'v1'}
        },
        'subtitle': {
          'runs': [
            {'text': 'Artist'},
            {'text': 'and more'},
          ]
        },
      }) as MediaItem;
      expect(video.id, 'v1');
      expect(video.artist, 'Artist');
    });
  });

  group('flex / fixed columns', () {
    test('getItemText tolerates a missing column', () {
      final row = {
        'flexColumns': [_flex('Only title')]
      };
      expect(getItemText(row, 0), 'Only title');
      expect(getItemText(row, 1), '');
      expect(getItemText(row, 1, noneIfAbsent: true), isNull);
      expect(getItemText(const {}, 0), '');
    });

    test('a duration sent as simpleText is read, not a null-check crash', () {
      final songs = parsePlaylistItems([
        _playlistRow('a', fixedText: {'simpleText': '3:45'}),
        _playlistRow('b', fixedText: {
          'runs': [
            {'text': '4:01'}
          ]
        }),
        _playlistRow('c'),
      ]).cast<MediaItem>();
      expect(songs.map((s) => s.id), ['a', 'b', 'c']);
      expect(songs.first.duration, const Duration(minutes: 3, seconds: 45));
      expect(
          songs.elementAt(1).duration, const Duration(minutes: 4, seconds: 1));
      expect(songs.last.duration, isNull);
    });

    test('a row without a title column does not drop the playlist', () {
      final songs = parsePlaylistItems([_playlistRow('x', withTitle: false)]);
      expect(songs, hasLength(1));
    });
  });

  test('parseSearchResults leaves out rows that are not results', () {
    final results = parseSearchResults(
      [
        // A song row without a playable video id parses to null.
        {
          'musicResponsiveListItemRenderer': {
            'flexColumns': [_flex('No id'), _flex('Artist')],
          }
        },
        // An album row without a browse id parses to {}.
        {
          'musicResponsiveListItemRenderer': {
            'flexColumns': [_flex('Album'), _flex('Album')],
          }
        },
        {'somethingElse': {}},
      ],
      ['artist', 'playlist', 'song', 'video', 'station'],
      null,
      'Top result',
    );
    expect(results, isEmpty);
  });

  test('one malformed home card does not cost the whole shelf', () {
    final home = parseMixedContent([
      {
        'musicCarouselShelfRenderer': {
          'header': {
            'musicCarouselShelfBasicHeaderRenderer': {
              'title': {
                'runs': [
                  {'text': 'Mixed for you'}
                ]
              }
            }
          },
          'contents': [
            // Playlist card whose subtitle is not a map: used to throw.
            {
              'musicTwoRowItemRenderer': {
                'title': {
                  'runs': [
                    {
                      'text': 'Broken',
                      'navigationEndpoint': {
                        'browseEndpoint': {
                          'browseId': 'VLPL1',
                          'browseEndpointContextSupportedConfigs': {
                            'browseEndpointContextMusicConfig': {
                              'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                'subtitle': 'not a map',
              }
            },
            {
              'musicTwoRowItemRenderer': {
                'title': {
                  'runs': [
                    {
                      'text': 'Good',
                      'navigationEndpoint': {
                        'browseEndpoint': {
                          'browseId': 'VLPL2',
                          'browseEndpointContextSupportedConfigs': {
                            'browseEndpointContextMusicConfig': {
                              'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                            }
                          }
                        }
                      }
                    }
                  ]
                },
                'subtitle': {
                  'runs': [
                    {'text': 'Playlist'}
                  ]
                },
              }
            },
          ],
        }
      },
      'not a row',
    ]);
    expect(home, hasLength(1));
    expect(home.single['title'], 'Mixed for you');
    final contents = home.single['contents'] as List;
    expect(contents.single, isA<Playlist>());
    expect((contents.single as Playlist).title, 'Good');
  });

  test('a continuation page of another type ends paging', () async {
    final res = await getContinuations(
      {},
      'musicShelfContinuation',
      10,
      (_) async => {
        'continuationContents': {
          'sectionListContinuation': {'contents': []}
        }
      },
      (dynamic contents) => List.from(contents as List),
      isAdditionparamReturnReq: true,
      additionalParams_: getContinuationString('seed'),
    );
    expect(res[0], isEmpty);
    expect(res[1], getContinuationString(null));
  });
}
