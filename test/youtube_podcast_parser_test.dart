import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/youtube_podcast_service.dart';

Map _fixture(String name) =>
    jsonDecode(File('test/fixtures/yt_podcasts/$name.json').readAsStringSync())
        as Map;

void main() {
  group('shows', () {
    test('popular shows parse title, playlist, cover, badge and author', () {
      final shows = YoutubePodcastParser.showsFrom(_fixture('popular_shows'));
      expect(shows, hasLength(5));
      for (final s in shows) {
        expect(s.playlistId, startsWith('PL'));
        expect(s.title, isNotEmpty);
        expect(s.thumbnailUrl, startsWith('https://'));
        expect(s.episodeCountText, contains('episodes'));
        expect(s.author, isNotEmpty);
        expect(s.authorId, startsWith('UC'));
      }
      final first = shows.first;
      expect(first.title, 'Financial Audit');
      expect(first.playlistId, 'PLzJVLNWKVr6ksDjycE7NpSptOlcaEP-jQ');
      expect(first.author, 'Caleb Hammer');
      expect(first.authorId, 'UCLe_q9axMaeTbjN0hy1Z9xA');
      expect(first.episodeCountText, '594 episodes');
      expect(first.updatedText, 'Updated 2 days ago');
      expect(first.thumbnailUrl, contains('studio_square_thumbnail'));
      expect(first.thumbnailUrl, contains('CNAFENAF')); // the 720px source
    });

    test('toJson/fromJson round-trips', () {
      final s = YoutubePodcastParser.showsFrom(_fixture('popular_shows')).first;
      final back = YtPodcastShow.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.toJson(), s.toJson());
    });

    test('search keeps only podcast lockups', () {
      final shows = YoutubePodcastParser.showsFrom(_fixture('search_shows'));
      expect(shows.map((s) => s.title), [
        'The Rest Is History',
        "Dan Snow's History Hit",
        'HISTORY This Week | Podcast',
      ]);
      expect(shows.every((s) => s.playlistId.startsWith('PL')), isTrue);
      expect(shows.first.episodeCountText, '493 episodes');
      expect(shows.first.updatedText, 'Updated 2 days ago');
      expect(shows.first.authorId, 'UCUYK0BJZF3yNb2fw1EdAXUQ');
    });

    test('channel Podcasts tab falls back to the channel as author', () {
      final shows =
          YoutubePodcastParser.showsFrom(_fixture('channel_podcasts'));
      expect(shows, hasLength(1));
      final s = shows.single;
      expect(s.playlistId, 'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA');
      expect(s.title, 'Nightcap');
      expect(s.author, 'Nightcap');
      expect(s.authorId, 'UCKnodHJpZd8UbSvAufDd3_g');
      expect(s.episodeCountText, '831 episodes');
      expect(s.updatedText, 'Updated yesterday');
    });
  });

  group('episodes', () {
    test('popular episodes come from videoRenderer items', () {
      final eps = YoutubePodcastParser.popularEpisodesFrom(
          _fixture('popular_episodes'));
      expect(eps, hasLength(5));
      for (final e in eps) {
        expect(e.id, matches(RegExp(r'^[\w-]{11}$')));
        expect(e.title, isNotEmpty);
        expect(e.artist, isNotEmpty);
        expect(e.duration!.inSeconds, greaterThan(0));
        expect(e.artUri.toString(), startsWith('https://i.ytimg.com/'));
      }
      final first = eps.first;
      expect(first.id, 'ms5nzJr80jw');
      expect(first.artist, 'Nightcap');
      expect(first.duration, const Duration(hours: 2, minutes: 58, seconds: 6));
      expect(first.extras!['length'], '2:58:06');
      expect(first.extras!['date'], 'Streamed 2 days ago');
      expect(first.extras!['description'], startsWith('Shannon Sharpe'));
      expect(first.extras!['artists'], [
        {'name': 'Nightcap', 'id': 'UCKnodHJpZd8UbSvAufDd3_g'}
      ]);
      expect(first.extras!.containsKey('podcastPlaylistId'), isFalse);
    });

    test('show page yields video lockups and the list continuation', () {
      final page = YoutubePodcastParser.episodesFrom(_fixture('show_episodes'),
          playlistId: 'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA');
      expect(page.episodes, hasLength(4));
      final first = page.episodes.first;
      expect(first.id, 'lQhxPrZ2UoQ');
      expect(first.title, startsWith('Unc Ocho & Iso react to Bears'));
      expect(first.artist, 'Nightcap');
      expect(
          first.duration, const Duration(hours: 2, minutes: 42, seconds: 16));
      expect(first.extras!['date'], 'Streamed 1 day ago');
      expect(first.extras!['artists'][0]['id'], 'UCKnodHJpZd8UbSvAufDd3_g');
      expect(first.extras!['podcastPlaylistId'],
          'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA');
      // The token sitting next to the videos, not the section-level one.
      expect(page.continuation, startsWith('4qmFsgKBARIkVkxQTHE5'));
    });

    test('continuation page parses and carries the next token', () {
      final page = YoutubePodcastParser.episodesFrom(
          _fixture('show_episodes_continuation'));
      expect(page.episodes, hasLength(4));
      expect(page.episodes.first.id, 'cJQiPZ7N_PQ');
      expect(page.episodes.first.duration!.inSeconds, greaterThan(0));
      expect(page.continuation, isNotEmpty);
    });

    test('legacy playlistVideoRenderer shape is supported', () {
      final page = YoutubePodcastParser.episodesFrom({
        'contents': [
          {
            'playlistVideoRenderer': {
              'videoId': 'abcdefghijk',
              'title': {
                'runs': [
                  {'text': 'Ep 1'}
                ]
              },
              'shortBylineText': {
                'runs': [
                  {
                    'text': 'Show',
                    'navigationEndpoint': {
                      'browseEndpoint': {'browseId': 'UCxyz'}
                    }
                  }
                ]
              },
              'lengthSeconds': '3725',
              'videoInfo': {
                'runs': [
                  {'text': '1K views'},
                  {'text': ' • '},
                  {'text': '3 days ago'}
                ]
              },
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg'}
                ]
              },
            }
          },
          {
            'continuationItemRenderer': {
              'continuationEndpoint': {
                'continuationCommand': {'token': 'NEXT'}
              }
            }
          },
        ],
      });
      final e = page.episodes.single;
      expect(e.title, 'Ep 1');
      expect(e.artist, 'Show');
      expect(e.duration, const Duration(hours: 1, minutes: 2, seconds: 5));
      expect(e.extras!['length'], '1:02:05');
      expect(e.extras!['date'], '3 days ago');
      expect(page.continuation, 'NEXT');
    });

    test('episodes are tagged as YouTube podcast episodes', () {
      final e = YoutubePodcastParser.episodesFrom(_fixture('show_episodes'),
              playlistId: 'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA')
          .episodes
          .first;
      final x = e.extras!;
      expect(x['podcastSource'], 'yt_podcast');
      expect(x['isPodcast'], isTrue);
      expect(x['showVideo'], isTrue);
      expect(x['videoType'], 'MUSIC_VIDEO_TYPE_UGC');
      expect(x['resultType'], 'video');
      expect(x.containsKey('url'), isTrue);
      expect(x['url'], isNull);
    });

    test('MediaItemBuilder round-trip keeps podcast fields', () {
      final e = YoutubePodcastParser.episodesFrom(_fixture('show_episodes'),
              playlistId: 'PLq9fVK72pJBIzzgr5KQkVJOo4FZrDbCxA')
          .episodes
          .first;
      final back = MediaItemBuilder.fromJson(
          jsonDecode(jsonEncode(MediaItemBuilder.toJson(e))));
      expect(back.id, e.id);
      expect(back.title, e.title);
      expect(back.artist, e.artist);
      expect(back.duration, e.duration);
      expect(back.artUri, e.artUri);
      for (final k in [
        'isPodcast',
        'showVideo',
        'podcastSource',
        'podcastPlaylistId',
        'videoType',
        'resultType',
        'url',
        'artists',
        'date',
        'length',
        'description',
      ]) {
        expect(back.extras![k], e.extras![k], reason: k);
      }
    });

    test('parseClock handles H:MM:SS, M:SS and rejects labels', () {
      expect(YoutubePodcastParser.parseClock('2:58:06'),
          const Duration(hours: 2, minutes: 58, seconds: 6));
      expect(YoutubePodcastParser.parseClock('4:05'),
          const Duration(minutes: 4, seconds: 5));
      expect(YoutubePodcastParser.parseClock('LIVE'), isNull);
      expect(YoutubePodcastParser.parseClock(null), isNull);
    });
  });
}
