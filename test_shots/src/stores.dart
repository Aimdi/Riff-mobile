import 'dart:io';
import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart'
    show episodeSnapshot;
import 'package:harmonymusic/services/search_recents.dart';
import 'package:harmonymusic/services/spotify_api_service.dart';
import 'package:harmonymusic/services/spotify_auth_service.dart';
import 'package:harmonymusic/services/spotify_home.dart';
import 'package:harmonymusic/services/spotify_import_service.dart';
import 'package:harmonymusic/ui/screens/Home/home_feed_data.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';
import 'package:hive/hive.dart';

import 'env.dart';
import 'media_data.dart';
import 'sample_data.dart';

/// The accent the shots use: green (the default), or the one named by
/// `--dart-define=SHOT_ACCENT=Blue` (Violet, Crimson, Amber, Cyan: see
/// ThemeController.riffAccents).
const shotAccentName = String.fromEnvironment('SHOT_ACCENT');

Color get shotAccent =>
    ThemeController.riffAccents[shotAccentName] ??
    ThemeController.riffAccents['Green']!;

/// The library, history and stats the screens read, written into the
/// in-memory Hive boxes ([openShotBoxes]) before each scenario.
Future<void> seedShotStores() async {
  await clearShotBoxes();
  final now = DateTime.now().millisecondsSinceEpoch;

  // ── App preferences ─────────────────────────────────────────────────
  await Hive.box('AppPrefs').putAll({
    'themeModeType': 2, // dark: the Lights out theme
    'riffAccentColor': shotAccent.value,
    'cacheSongs': false,
    'skipSilenceEnabled': false,
    'sponsorBlockEnabled': true,
    'streamingQuality': 1,
    'discoverContentType': 'QP',
    'cacheHomeScreenData': true,
    'slidableActionEnabled': true,
    'currentAppLanguageCode': 'en',
    // Two things pinned to Speed dial from a shelf's menu.
    SpeedDialPins.key: [
      SpeedDialPin.of(ShotData.album(15))!.toJson(),
      SpeedDialPin.of(ShotData.userPlaylist(4))!.toJson(),
    ],
    // Spotify connected, its shelves cached (see [_spotifyShelves]).
    SpotifyHome.cacheKey: encodeSpotifyShelves(_spotifyShelves()),
    SpotifyHome.cacheAtKey: now,
  });
  // Signed in to Spotify (the tokens live in secure storage, stubbed).
  await SecureCredentials.set(SpotifyAuthService.kAccessToken, 'shot');
  await SecureCredentials.set(SpotifyAuthService.kRefreshToken, 'shot');

  // ── Recently played (Speed dial), favourites, cached / downloaded ───
  // Oldest first: Home lists them newest first.
  final recent = ShotData.songs(1, 19).reversed;
  await Hive.box('LIBRP').addAll([for (final s in recent) _json(s)]);
  await Hive.box('LIBFAV').putAll({
    for (final s in ShotData.songs(1, 15)) s.id: _json(s),
  });
  // Songs tab: 22 songs, some downloaded, the rest cached from listening.
  final library = ShotData.songs(0, 22);
  await Hive.box('SongDownloads').putAll({
    for (final s in library.take(8)) s.id: _json(s),
  });
  await Hive.box('SongsCache').putAll({
    for (final s in library.skip(8)) s.id: _json(s),
  });

  // ── Library playlists, albums, artists ─────────────────────────────
  await Hive.box('LibraryPlaylists').putAll({
    for (final p in ShotData.userPlaylists) p.playlistId: p.toJson(),
  });
  for (final (i, p) in ShotData.userPlaylists.indexed) {
    final box = await openShotBox(p.playlistId);
    await box.clear();
    await box.addAll([
      for (final s in ShotData.userPlaylistSongs(i,
          count: int.parse(p.songCount ?? '12').clamp(1, 24)))
        _json(s)
    ]);
  }
  await Hive.box('LibraryAlbums').putAll({
    for (final a in ShotData.albums.take(12)) a.browseId: a.toJson(),
  });
  for (final a in ShotData.albums.take(12)) {
    final box = await openShotBox(a.browseId);
    await box.clear();
    await box.addAll([for (final s in ShotData.albumTracks(a.title)) _json(s)]);
  }
  await Hive.box('LibraryArtists').putAll({
    for (final a in ShotData.artists.take(14)) a.browseId: a.toJson(),
  });

  // ── Stats: "Your week" and the Stats screen ─────────────────────────
  final today = DateTime.now();
  const plays = [14, 22, 9, 31, 18, 26, 12];
  for (var d = 0; d < 7; d++) {
    final day = today.subtract(Duration(days: 6 - d));
    await Hive.box('DailyStats').put(_dayKey(day), {
      'plays': plays[d],
      'seconds': plays[d] * 205,
      'skips': d % 3,
    });
  }
  for (final (i, s) in ShotData.songs(0, 30).indexed) {
    await Hive.box('SongStats').put(s.id, {
      'title': s.title,
      'artist': s.artist,
      'plays': 40 - i,
      'seconds': (40 - i) * 200,
      'lastPlayed': now - i * 3600000,
      'lastSource': 'home',
    });
  }

  // ── Podcasts ───────────────────────────────────────────────────────
  await Hive.box('PodcastSubs').putAll({
    for (final s in ShotPods.shows) s.feedUrl: s.subscription,
  });
  await Hive.box('LibraryPodcasts').putAll({
    for (var i = 0; i < 2; i++)
      ShotPods.ytShow(i).playlistId: {
        ...ShotPods.ytShow(i).toJson(),
        'kind': 'podcast',
        'addedAt': now - i * 86400000,
      },
  });
  // A followed show's page keeps its episodes in a box of its own.
  for (var i = 0; i < 2; i++) {
    await (await openShotBox(ShotPods.ytShow(i).playlistId)).clear();
  }
  for (final (n, (show, ep, heard)) in ShotPods.inProgress.indexed) {
    final e = ShotPods.episode(show, ep);
    final total = e.duration!.inMilliseconds;
    await Hive.box('PodcastProgress').put(e.id, {
      'id': e.id,
      'title': e.title,
      'artist': e.artist,
      'artUri': e.artUri.toString(),
      'url': e.extras!['url'],
      'feedUrl': show.feedUrl,
      'description': e.extras!['description'],
      'positionMs': (total * heard).round(),
      'durationMs': total,
      'updatedAt': now - n * 3600000,
    });
  }
  for (final (show, ep) in ShotPods.played) {
    await Hive.box('PodcastPlayed').put(ShotPods.episodeId(show, ep), now);
  }
  await Hive.box('PodcastQueue').put('items', [
    for (final (show, ep) in ShotPods.queue)
      _queueMap(ShotPods.episode(show, ep))
  ]);
  final downloads = Directory('${shotTmp.path}/podcasts')
    ..createSync(recursive: true);
  for (final (show, ep) in ShotPods.downloads) {
    final e = ShotPods.episode(show, ep);
    final path = '${downloads.path}/${e.id}.mp3';
    File(path).writeAsBytesSync(const [0]);
    await Hive.box('PodcastDownloads').put(e.id, {
      ..._queueMap(e),
      'path': path,
    });
  }
  for (final (n, (show, ep)) in ShotPods.history.indexed) {
    final e = ShotPods.episode(show, ep);
    await Hive.box('PodcastHistory').put(e.id, {
      'playedAt': now - n * 5 * 3600000,
      'episode': episodeSnapshot(e),
    });
  }
  for (final (n, (show, ep)) in ShotPods.starred.indexed) {
    final e = ShotPods.episode(show, ep);
    await Hive.box('PodcastStarred').put(e.id, {
      'starredAt': now - n * 2 * 86400000,
      'episode': episodeSnapshot(e),
    });
  }

  // ── Audiobooks ─────────────────────────────────────────────────────
  final free = ShotBooks.free;
  await Hive.box('SavedFreeAudiobooks').putAll({
    for (final b in [free[3], free[6], free[1], free[0]]) b.id: b.toJson(),
  });
  await Hive.box('SavedAudiobooks').putAll({
    for (final b in ShotBooks.store.take(3)) b.id: b.toJson(),
  });
  for (final (n, (book, chapter, heard)) in [
    (free[0], 6, 0.35),
    (free[1], 2, 0.71),
  ].indexed) {
    const totalMs = 1882000;
    await Hive.box('AudiobookProgress').put('lv_${book.id}_$chapter', {
      'id': 'lv_${book.id}_$chapter',
      'bookId': book.id,
      'title': ShotBooks.chapterTitles[chapter],
      'album': book.title,
      'artist': book.author,
      'artUri': book.cover,
      'url': 'https://archive.org/download/${book.id}/$chapter.mp3',
      'trackIndex': chapter,
      'trackCount': ShotBooks.chapterTitles.length,
      'positionMs': (totalMs * heard).round(),
      'durationMs': totalMs,
      'updatedAt': now - (n + 1) * 7200000,
    });
  }

  // ── Search history ─────────────────────────────────────────────────
  // What was opened from search (newest first), then the words searched.
  await Hive.box('AppPrefs').put(SearchRecents.key, [
    for (final item in <Object>[
      ShotData.artists[5],
      ShotData.song(16),
      ShotData.album(6),
      ShotData.ytPlaylist(6),
    ])
      SearchRecent.of(item)!.toJson()
  ]);
  await Hive.box('searchQuery').addAll(const [
    'lofi beats to study to',
    'kaito moriyama',
    'fuego lento marisol vega',
    'best of 2025',
    'nova hart live',
    'rainy day jazz',
  ]);
}

Map<String, dynamic> _json(MediaItem s) => MediaItemBuilder.toJson(s);

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// An episode as the podcast queue (and downloads) store it.
Map<String, dynamic> _queueMap(MediaItem m) => {
      'id': m.id,
      'title': m.title,
      'artist': m.artist,
      'artUri': m.artUri?.toString(),
      'durationMs': m.duration?.inMilliseconds,
      'url': m.extras?['url'],
      'isPodcast': true,
      'feedUrl': m.extras?['feedUrl'],
      'date': m.extras?['date'],
      'pubDateMs': m.extras?['pubDateMs'],
      'description': m.extras?['description'],
    };

/// Spotify shelves as Home caches them: what you played, on repeat, top
/// artists and new releases. Names differ from the YouTube catalogue so
/// "each item once" keeps them all.
List<SpotifyShelf> _spotifyShelves() {
  String art(String s) => ShotData.coverUrl('spotify $s');
  const tracks = [
    ('Glasshouse Summer', 'Wren & Wolf'),
    ('Tidal', 'Mira Solenne'),
    ('Cold Coffee, Warm Hands', 'The Understudies'),
    ('Ferris Wheel', 'Koji Arakawa'),
    ('Ojos Cerrados', 'Lucía Ferrer'),
    ('Satellites & Sparrows', 'Halden Park'),
    ('Polaroid', 'Wren & Wolf'),
    ('Low Orbit', 'Mira Solenne'),
  ];
  const albums = [
    ('Midnight Atlas', 'Halden Park', '2026'),
    ('Soft Machines', 'Koji Arakawa', '2026'),
    ('Paper Lanterns', 'Lucía Ferrer', '2026'),
    ('The Understudies (Deluxe Edition)', 'The Understudies', '2026'),
    ('Cartography', 'Mira Solenne', '2026'),
    ('Northern Soul', 'Wren & Wolf', '2026'),
  ];
  const artists = [
    'Wren & Wolf',
    'Mira Solenne',
    'Koji Arakawa',
    'Lucía Ferrer',
    'Halden Park',
    'The Understudies',
  ];
  final playlists = [
    for (final (i, name) in const [
      'Discover Weekly Archive',
      'Running 170 BPM',
      'Liked Songs Overflow',
      'Dinner Party',
      'Shower Concerts',
    ].indexed)
      SpotifyHomePlaylist(
          SpotifyPlaylistSummary(
              id: 'sppl$i',
              name: name,
              coverUrl: art('pl $name'),
              trackCount: 20 + i * 7,
              ownerName: 'you'),
          readable: true),
  ];
  return [
    SpotifyShelf(SpotifyShelfId.jumpBackIn, [
      ...playlists.take(3),
      for (final (i, (name, artist, year)) in albums.take(3).indexed)
        SpotifyAlbumSummary(
            id: 'spjb$i',
            name: name,
            artists: artist,
            coverUrl: art('album $name'),
            year: year),
    ]),
    SpotifyShelf(SpotifyShelfId.onRepeat, [
      SpotifyTasteMix([for (final (t, _) in tracks.take(4)) art('track $t')]),
      for (final (i, (title, artist)) in tracks.indexed)
        SpotifyTrackRef(
            id: 'sptr$i',
            title: title,
            artists: artist,
            durationMs: 200000 + i * 9000,
            artUrl: art('track $title')),
    ]),
    SpotifyShelf(SpotifyShelfId.topArtists, [
      for (final (i, name) in artists.indexed)
        SpotifyArtistSummary(
            id: 'spar$i', name: name, imageUrl: art('artist $name')),
    ]),
    SpotifyShelf(SpotifyShelfId.newReleases, [
      for (final (i, (name, artist, year)) in albums.skip(3).indexed)
        SpotifyAlbumSummary(
            id: 'spnr$i',
            name: name,
            artists: artist,
            coverUrl: art('album $name'),
            year: year,
            releaseDate: '$year-10-0${i + 1}'),
    ]),
  ];
}
