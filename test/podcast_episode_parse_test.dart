import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/nav_parser.dart';

/// Fixture matching current YouTube Music podcast shelf items
/// (`musicMultiRowListItemRenderer`).
Map<String, dynamic> _multiRowEpisode({
  required String videoId,
  required String title,
  String duration = '1 hr 31 min',
  String date = '2h ago',
}) {
  return {
    'musicMultiRowListItemRenderer': {
      'thumbnail': {
        'musicThumbnailRenderer': {
          'thumbnail': {
            'thumbnails': [
              {
                'url': 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                'width': 400,
                'height': 225,
              }
            ]
          }
        }
      },
      'overlay': {
        'musicItemThumbnailOverlayRenderer': {
          'content': {
            'musicPlayButtonRenderer': {
              'playNavigationEndpoint': {
                'watchEndpoint': {
                  'videoId': videoId,
                  'watchEndpointMusicSupportedConfigs': {
                    'watchEndpointMusicConfig': {
                      'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
                    }
                  }
                }
              }
            }
          }
        }
      },
      'onTap': {
        'watchEndpoint': {
          'videoId': videoId,
          'watchEndpointMusicSupportedConfigs': {
            'watchEndpointMusicConfig': {
              'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
            }
          }
        }
      },
      'subtitle': {
        'runs': [
          {'text': date}
        ]
      },
      'playbackProgress': {
        'musicPlaybackProgressRenderer': {
          'durationText': {
            'runs': [
              {'text': ' • '},
              {'text': duration},
            ]
          }
        }
      },
      'title': {
        'runs': [
          {
            'text': title,
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'MPED$videoId'}
            }
          }
        ]
      },
      'description': {
        'runs': [
          {'text': 'Episode description'}
        ]
      },
    }
  };
}

Map<String, dynamic> _responsiveEpisode({
  required String videoId,
  required String title,
}) {
  return {
    'musicResponsiveListItemRenderer': {
      'playlistItemData': {'videoId': videoId},
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': title}
              ]
            }
          }
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'Some Podcast'}
              ]
            }
          }
        },
      ],
      'thumbnail': {
        'musicThumbnailRenderer': {
          'thumbnail': {
            'thumbnails': [
              {
                'url': 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
              }
            ]
          }
        }
      },
      'overlay': {
        'musicItemThumbnailOverlayRenderer': {
          'content': {
            'musicPlayButtonRenderer': {
              'playNavigationEndpoint': {
                'watchEndpoint': {
                  'videoId': videoId,
                  'watchEndpointMusicSupportedConfigs': {
                    'watchEndpointMusicConfig': {
                      'musicVideoType': 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE',
                    }
                  }
                }
              }
            }
          }
        }
      },
    }
  };
}

void main() {
  test('parsePodcastEpisodes handles multi-row cards (current YTM)', () {
    final contents = [
      _multiRowEpisode(videoId: 'abc123', title: 'Episode One'),
      _multiRowEpisode(videoId: 'def456', title: 'Episode Two', duration: '25 min'),
    ];
    final episodes = parsePodcastEpisodes(contents);
    expect(episodes.length, 2);
    expect(episodes[0].id, 'abc123');
    expect(episodes[0].title, 'Episode One');
    expect(episodes[0].duration, isNotNull);
    expect(episodes[0].duration!.inMinutes, greaterThan(0));
    expect(episodes[1].id, 'def456');
    expect(episodes[1].title, 'Episode Two');
  });

  test('parsePodcastEpisodes still handles responsive list items', () {
    final contents = [
      _responsiveEpisode(videoId: 'xyz789', title: 'Legacy Episode'),
    ];
    final episodes = parsePodcastEpisodes(contents);
    expect(episodes.length, 1);
    expect(episodes[0].id, 'xyz789');
    expect(episodes[0].title, 'Legacy Episode');
  });

  test('parsePodcastEpisodes skips unknown item shapes', () {
    final episodes = parsePodcastEpisodes([
      {'musicCardShelfRenderer': {}},
      _multiRowEpisode(videoId: 'ok1', title: 'Good'),
    ]);
    expect(episodes.length, 1);
    expect(episodes[0].id, 'ok1');
  });
}
