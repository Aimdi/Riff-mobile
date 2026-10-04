import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_home.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_builder.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';

SpotifyAlbumSummary album(String id, String date) =>
    SpotifyAlbumSummary(id: id, name: 'Album $id', releaseDate: date);

void main() {
  final now = DateTime(2026, 10, 4);

  group('new releases', () {
    test('within 28 days, any precision but year-only', () {
      expect(releasedWithin('2026-09-30', now), isTrue);
      expect(releasedWithin('2026-09-06', now), isTrue);
      expect(releasedWithin('2026-09-05', now), isFalse);
      expect(releasedWithin('2026-10', now), isTrue);
      expect(releasedWithin('2026', now), isFalse);
      expect(releasedWithin('2026-11-01', now), isFalse, reason: 'future');
      expect(releasedWithin(null, now), isFalse);
      expect(releasedWithin('garbage', now), isFalse);
    });

    test('newest first, each album once', () {
      final out = newReleasesFrom([
        [album('a', '2026-09-20'), album('old', '2025-01-01')],
        [album('b', '2026-10-01'), album('a', '2026-09-20')],
      ], now);
      expect(out.map((a) => a.id), ['b', 'a']);
    });

    test('followed artists are checked a rotating handful at a time', () {
      expect(rotatingWindow(30, 0, 12), [for (var i = 0; i < 12; i++) i]);
      expect(rotatingWindow(30, 24, 12).first, 24);
      expect(rotatingWindow(30, 24, 12).last, 5);
      expect(rotatingWindow(5, 3, 12), [3, 4, 0, 1, 2]);
      expect(rotatingWindow(0, 0, 12), isEmpty);
    });
  });

  group('jump back in', () {
    const t = SpotifyTrackRef(id: 't', title: 'T', artists: 'A');
    final al = album('al1', '2020-01-01');
    test('one card per album / playlist / artist played from, newest first',
        () {
      final plays = [
        SpotifyRecentPlay(track: t, contextUri: 'spotify:album:al1', album: al),
        const SpotifyRecentPlay(track: t, contextUri: 'spotify:playlist:p1'),
        SpotifyRecentPlay(track: t, contextUri: 'spotify:album:al1', album: al),
        const SpotifyRecentPlay(track: t, contextUri: 'spotify:playlist:gone'),
        const SpotifyRecentPlay(track: t, contextUri: 'spotify:artist:ar1'),
        const SpotifyRecentPlay(track: t),
      ];
      const pl = SpotifyHomePlaylist(
          SpotifyPlaylistSummary(id: 'p1', name: 'Mine'),
          readable: true);
      const ar = SpotifyArtistSummary(id: 'ar1', name: 'Artist');
      final out =
          jumpBackInFrom(plays, playlists: {'p1': pl}, artists: {'ar1': ar});
      expect(out, [al, pl, ar]);
    });

    test('recently-played keeps the context', () {
      final body = jsonEncode({
        'items': [
          {
            'played_at': '2026-10-03T20:00:00Z',
            'context': {'type': 'album', 'uri': 'spotify:album:x'},
            'track': {
              'id': 's1',
              'name': 'Song',
              'artists': [
                {'name': 'A'}
              ],
              'album': {'id': 'x', 'name': 'Album', 'release_date': '2026-09'}
            }
          },
          {
            'context': null,
            'track': {'id': 's2', 'name': 'Two', 'artists': []}
          },
        ]
      });
      final plays = SpotifyApiService.parseRecentPlays(body);
      expect(plays.length, 2);
      expect(plays[0].contextUri, 'spotify:album:x');
      expect(plays[0].album!.releaseDate, '2026-09');
      expect(plays[0].playedAt, DateTime.utc(2026, 10, 3, 20));
      expect(plays[1].contextUri, isNull);
    });
  });

  test('cached shelves survive a round trip', () {
    final shelves = [
      const SpotifyShelf(SpotifyShelfId.onRepeat, [
        SpotifyTasteMix(['u1', 'u2']),
        SpotifyTrackRef(
            id: 't1', title: 'T', artists: 'A', isrc: 'X1', artUrl: 'u1'),
      ]),
      SpotifyShelf(SpotifyShelfId.newReleases, [album('a1', '2026-09-30')]),
      const SpotifyShelf(SpotifyShelfId.playlists, [
        SpotifyHomePlaylist(
            SpotifyPlaylistSummary(id: 'p', name: 'P', ownerName: 'me'),
            readable: true)
      ]),
      const SpotifyShelf(SpotifyShelfId.topArtists,
          [SpotifyArtistSummary(id: 'ar', name: 'Ar', imageUrl: 'img')]),
    ];
    final back = decodeSpotifyShelves(encodeSpotifyShelves(shelves));
    expect(back.map((s) => s.id), shelves.map((s) => s.id));
    final mix = back[0].items[0] as SpotifyTasteMix;
    expect(mix.covers, ['u1', 'u2']);
    final track = back[0].items[1] as SpotifyTrackRef;
    expect([track.id, track.isrc, track.artUrl], ['t1', 'X1', 'u1']);
    expect((back[1].items.single as SpotifyAlbumSummary).releaseDate,
        '2026-09-30');
    final pl = back[2].items.single as SpotifyHomePlaylist;
    expect([pl.playlist.id, pl.readable, pl.playlist.ownerName],
        ['p', true, 'me']);
    expect((back[3].items.single as SpotifyArtistSummary).imageUrl, 'img');
    expect(decodeSpotifyShelves('not json'), isEmpty);
    expect(decodeSpotifyShelves(null), isEmpty);
  });

  group('on Home', () {
    test('the same song from two sources is one song', () {
      expect(titleArtistKey('Get Lucky (Radio Edit)', 'Daft Punk, Pharrell'),
          titleArtistKey('Get Lucky', 'Daft Punk'));
      expect(titleArtistKey('Hey Jude - Remastered 2015', 'The Beatles'),
          titleArtistKey('Hey Jude', 'The Beatles'));
      expect(
          titleArtistKey('Hey', 'A'), isNot(titleArtistKey('Hey Jude', 'A')));
    });

    HomeItem song(String id, String title, String artist) =>
        HomeItem('song:$id', id, altKey: titleArtistKey(title, artist));
    HomeItem sp(String id, String title, String artist) =>
        HomeItem('sp:track:$id', id, altKey: titleArtistKey(title, artist));

    test('Spotify shelves come after your mixes, before Your week', () {
      final s = buildHomeSections(HomeFeedInput(
        personalized: [
          HomeShelfData(id: 'm', title: 'Mixes', items: [song('m1', 'M', 'X')])
        ],
        spotify: [
          HomeShelfData(
              id: 'spotify:onRepeat',
              title: 'On repeat',
              items: [sp('1', 'One', 'A')])
        ],
        hasWeek: true,
      ));
      final order = [for (final m in s) m.section];
      expect(order.indexOf(HomeSection.spotify),
          order.indexOf(HomeSection.personalized) + 1);
      expect(order.indexOf(HomeSection.yourWeek),
          order.indexOf(HomeSection.spotify) + 1);
    });

    test('a Spotify song already on Home from YouTube Music is dropped', () {
      final s = buildHomeSections(HomeFeedInput(
        quickPicks: [song('yt1', 'Get Lucky', 'Daft Punk')],
        spotify: [
          HomeShelfData(id: 'spotify:onRepeat', title: 'On repeat', items: [
            sp('s1', 'Get Lucky (Radio Edit)', 'Daft Punk'),
            sp('s2', 'Around the World', 'Daft Punk'),
          ])
        ],
      ));
      final shelf =
          s.firstWhere((m) => m.section == HomeSection.spotify).shelves.single;
      expect(shelf.items.map((i) => i.key), ['sp:track:s2']);
    });

    test('switched off in Home layout: no Spotify shelves', () {
      final s = buildHomeSections(HomeFeedInput(
        spotify: [
          HomeShelfData(
              id: 'spotify:onRepeat',
              title: 'On repeat',
              items: [sp('1', 'One', 'A')])
        ],
        hidden: const {HomeSection.spotify},
      ));
      expect(s.map((m) => m.section), isNot(contains(HomeSection.spotify)));
    });
  });
}
