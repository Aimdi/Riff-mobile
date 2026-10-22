import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/models/album.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';

/// Made-up but realistic catalogue for the screenshots: names of mixed
/// lengths (some long enough to test ellipsis), covers from
/// [coverUrl] (drawn by covers.dart), dates relative to now.
class ShotData {
  ShotData._();

  /// A YouTube Music-style cover URL. The harness draws it (see
  /// covers.dart); the size suffix is what the app rewrites.
  static String coverUrl(String slug) =>
      'https://lh3.googleusercontent.com/riffshot/${_slug(slug)}=w544-h544-l90-rj';

  static String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  // ───────────────────────────────────────────────────────── artists ──

  static const artistNames = [
    'Nova Hart',
    'Odd Weather',
    'Saoirse Quinn',
    'DJ Halcyon',
    'The Lantern Society',
    'Kaito Moriyama',
    'Marisol Vega',
    'Juniper & The Strays',
    'Fenwick Lane Orchestra',
    'Theo Ashgrove',
    'Ellis Monroe',
    'Los Hermanos del Sur',
    'Aurora Vale',
    'Priya Raman',
    'Hollow Pines',
    'Sam Okafor',
  ];

  static String artistId(String name) =>
      'UCriff${_slug(name).replaceAll('-', '')}'.padRight(24, 'x');

  static final artists = [
    for (final (i, name) in artistNames.indexed)
      Artist(
        name: name,
        browseId: artistId(name),
        thumbnailUrl: coverUrl('artist $name'),
        subscribers: [
          '2.4M subscribers',
          '318K subscribers',
          '1.1M subscribers',
          '86K subscribers',
          '5.7M subscribers',
          '742K subscribers',
        ][i % 6],
      ),
  ];

  // ─────────────────────────────────────────────────────────── songs ──

  /// (title, artist, album, length).
  static const _songs = <(String, String, String, String)>[
    ('Paper Planes Over Lisbon', 'Nova Hart', 'Coastlines', '3:42'),
    ('Static Hearts', 'Odd Weather', 'Low Pressure', '3:18'),
    ('Golden Hour (Acoustic)', 'Saoirse Quinn', 'Field Notes', '4:05'),
    (
      'Never Let the Lights Go Out on Sunset Boulevard (Extended Club Mix)',
      'DJ Halcyon',
      'Afterglow Sessions, Vol. 2',
      '7:31'
    ),
    ('Velvet Underground Station', 'The Lantern Society', 'Lamplight', '4:12'),
    ('Kintsugi', 'Kaito Moriyama', 'Tokyo Rain Simulator', '3:57'),
    ('Corazón de Neón', 'Marisol Vega', 'Fuego Lento', '3:24'),
    ('Slow Burn', 'Juniper & The Strays', 'Wild Honey', '3:49'),
    (
      'Northern Lights, Southern Skies',
      'Fenwick Lane Orchestra',
      'Bloom',
      '5:06'
    ),
    ('Echoes in the Hallway', 'Theo Ashgrove', 'The Long Goodbye', '4:21'),
    ('Midnight Laundromat', 'Ellis Monroe', 'Postcards from Nowhere', '3:11'),
    ('Satellite Lullaby', 'Nova Hart', 'Coastlines', '4:44'),
    ('Run Like the River', 'Los Hermanos del Sur', 'Mariposa', '3:36'),
    (
      'Honey, I\'m Home (feat. Ellis Monroe)',
      'Saoirse Quinn',
      'Field Notes',
      '3:29'
    ),
    ('Glass Houses', 'Odd Weather', 'Low Pressure', '3:52'),
    ('Tokyo Rain Simulator', 'Kaito Moriyama', 'Tokyo Rain Simulator', '4:38'),
    (
      'All the Things We Never Said Out Loud Before the Summer Ended',
      'The Lantern Society',
      'Lamplight',
      '5:14'
    ),
    ('Daydream Believer Club', 'Juniper & The Strays', 'Wild Honey', '2:58'),
    ('Fuego Lento', 'Marisol Vega', 'Fuego Lento', '3:45'),
    ('Overpass', 'Theo Ashgrove', 'The Long Goodbye', '3:33'),
    ('Weightless', 'DJ Halcyon', 'Afterglow Sessions, Vol. 2', '6:02'),
    (
      'Postcards from Nowhere',
      'Ellis Monroe',
      'Postcards from Nowhere',
      '4:01'
    ),
    ('Moth to a Flame', 'Saoirse Quinn', 'Field Notes', '3:47'),
    ('Arcade Fire Drill', 'Odd Weather', 'Low Pressure', '2:44'),
    ('Winter in Kyoto', 'Kaito Moriyama', 'Tokyo Rain Simulator', '4:16'),
    ('Sunday Morning Static', 'Nova Hart', 'Coastlines', '3:22'),
    ('Bloom', 'Fenwick Lane Orchestra', 'Bloom', '6:48'),
    ('The Long Goodbye', 'Theo Ashgrove', 'The Long Goodbye', '5:27'),
    ('Lighthouse Keeper', 'The Lantern Society', 'Lamplight', '4:33'),
    ('Mariposa', 'Los Hermanos del Sur', 'Mariposa', '3:15'),
    ('Ultraviolet', 'Aurora Vale', 'Prism Season', '3:39'),
    ('Monsoon Letters', 'Priya Raman', 'Monsoon Letters', '4:27'),
    ('Pine Smoke', 'Hollow Pines', 'Cabin Fever Dreams', '3:58'),
    ('Lagos After Dark', 'Sam Okafor', 'City of Lights', '3:44'),
    ('Holding Pattern', 'Aurora Vale', 'Prism Season', '3:05'),
    ('Chai at 3AM', 'Priya Raman', 'Monsoon Letters', '2:51'),
    ('Firewood', 'Hollow Pines', 'Cabin Fever Dreams', '4:09'),
    ('Afrobeat Sunrise', 'Sam Okafor', 'City of Lights', '3:56'),
    ('Neon Tide', 'Nova Hart', 'Coastlines', '3:30'),
    ('Thunderstorm in a Teacup', 'Odd Weather', 'Low Pressure', '3:14'),
    ('Wildflower Wine', 'Juniper & The Strays', 'Wild Honey', '3:41'),
    ('Seventeen Summers', 'Ellis Monroe', 'Postcards from Nowhere', '3:58'),
    ('Bossa for a Rainy Day', 'Los Hermanos del Sur', 'Mariposa', '4:02'),
    ('Hymn for the Night Shift', 'Theo Ashgrove', 'The Long Goodbye', '4:48'),
    ('Paper Moon', 'Saoirse Quinn', 'Field Notes', '3:26'),
    ('Deep Blue Hour', 'DJ Halcyon', 'Afterglow Sessions, Vol. 2', '5:39'),
    ('Shinkansen', 'Kaito Moriyama', 'Tokyo Rain Simulator', '3:47'),
    ('La Última Canción', 'Marisol Vega', 'Fuego Lento', '4:11'),
    ('Copper Skies', 'Fenwick Lane Orchestra', 'Bloom', '5:52'),
    ('Kites', 'The Lantern Society', 'Lamplight', '3:19'),
    ('Afterimage', 'Aurora Vale', 'Prism Season', '3:28'),
    ('Rooftop Garden', 'Priya Raman', 'Monsoon Letters', '3:37'),
    ('Evergreen', 'Hollow Pines', 'Cabin Fever Dreams', '4:24'),
    ('Danfo Ride', 'Sam Okafor', 'City of Lights', '3:09'),
    ('Low Tide, High Hopes', 'Nova Hart', 'Coastlines', '3:54'),
    ('Barometer', 'Odd Weather', 'Low Pressure', '3:01'),
    ('Porch Light', 'Juniper & The Strays', 'Wild Honey', '3:33'),
    ('Cassette Summer', 'Ellis Monroe', 'Postcards from Nowhere', '3:46'),
    ('Sol de Medianoche', 'Los Hermanos del Sur', 'Mariposa', '3:57'),
    ('Night Bus to Nowhere', 'Theo Ashgrove', 'The Long Goodbye', '4:14'),
    ('Clover', 'Saoirse Quinn', 'Field Notes', '2:49'),
    ('Afterparty Prophecy', 'DJ Halcyon', 'Afterglow Sessions, Vol. 2', '6:21'),
    ('Sakura Static', 'Kaito Moriyama', 'Tokyo Rain Simulator', '3:43'),
    ('Mi Ciudad', 'Marisol Vega', 'Fuego Lento', '3:28'),
    ('Ember & Ash', 'Fenwick Lane Orchestra', 'Bloom', '4:59'),
    ('Fireflies in Jars', 'The Lantern Society', 'Lamplight', '3:52'),
    ('Refraction', 'Aurora Vale', 'Prism Season', '3:17'),
    ('Petrichor', 'Priya Raman', 'Monsoon Letters', '4:06'),
    ('North Face', 'Hollow Pines', 'Cabin Fever Dreams', '3:49'),
    ('Third Mainland Bridge', 'Sam Okafor', 'City of Lights', '4:18'),
  ];

  static int _seconds(String length) {
    final p = length.split(':').map(int.parse).toList();
    return p[0] * 60 + p[1];
  }

  static String songId(int i) => 'RiffSng${i.toString().padLeft(4, '0')}';

  static String albumId(String album) =>
      'MPREb_riff${_slug(album).replaceAll('-', '')}';

  /// A song as YouTube Music sends it (what MediaItemBuilder reads).
  static Map<String, dynamic> songJson(int i) {
    final (title, artist, album, length) = _songs[i % _songs.length];
    return {
      'videoId': songId(i),
      'title': title,
      'artists': [
        {'name': artist, 'id': artistId(artist)}
      ],
      'album': {'name': album, 'id': albumId(album)},
      'length': length,
      'duration': _seconds(length),
      'resultType': 'song',
      if (i % 9 == 4) 'isExplicit': true,
      // Each song its own art (real singles and albums differ; shared
      // album art would make every shelf look repetitive here).
      'thumbnails': [
        {'url': coverUrl('song $title $artist'), 'width': 544, 'height': 544}
      ],
    };
  }

  static MediaItem song(int i) => MediaItemBuilder.fromJson(songJson(i));

  static int get songCount => _songs.length;

  /// Songs [from] (inclusive) to [to] (exclusive).
  static List<MediaItem> songs(int from, int to) =>
      [for (var i = from; i < to; i++) song(i)];

  /// The song playing in every shot.
  static MediaItem get nowPlaying => song(0);

  // ────────────────────────────────────────────────────────── albums ──

  static const _albums = <(String, String, String, String)>[
    ('Coastlines', 'Nova Hart', '2024', 'Album'),
    ('Low Pressure', 'Odd Weather', '2023', 'Album'),
    ('Field Notes', 'Saoirse Quinn', '2025', 'Album'),
    ('Afterglow Sessions, Vol. 2', 'DJ Halcyon', '2024', 'EP'),
    ('Lamplight', 'The Lantern Society', '2022', 'Album'),
    ('Tokyo Rain Simulator', 'Kaito Moriyama', '2025', 'Album'),
    ('Fuego Lento', 'Marisol Vega', '2024', 'Album'),
    ('Wild Honey', 'Juniper & The Strays', '2021', 'Album'),
    ('Bloom', 'Fenwick Lane Orchestra', '2023', 'Album'),
    ('The Long Goodbye', 'Theo Ashgrove', '2025', 'Album'),
    ('Postcards from Nowhere', 'Ellis Monroe', '2024', 'Single'),
    ('Mariposa', 'Los Hermanos del Sur', '2022', 'Album'),
    ('Prism Season', 'Aurora Vale', '2025', 'EP'),
    ('Monsoon Letters', 'Priya Raman', '2024', 'Album'),
    ('Cabin Fever Dreams', 'Hollow Pines', '2023', 'Album'),
    ('City of Lights', 'Sam Okafor', '2025', 'Album'),
  ];

  static Album album(int i) {
    final (title, artist, year, type) = _albums[i % _albums.length];
    return Album(
      title: title,
      browseId: albumId(title),
      artists: [
        {'name': artist, 'id': artistId(artist)}
      ],
      year: year,
      description: type,
      audioPlaylistId: 'OLAK5uy_riff$i',
      thumbnailUrl: coverUrl('album $title'),
    );
  }

  static List<Album> get albums =>
      [for (var i = 0; i < _albums.length; i++) album(i)];

  /// The album's songs, in track order.
  static List<MediaItem> albumTracks(String albumTitle) => [
        for (var i = 0; i < _songs.length; i++)
          if (_songs[i].$3 == albumTitle) song(i)
      ];

  // ─────────────────────────────────────────────────────── playlists ──

  static const _playlists = <(String, String, int)>[
    ('Late Night Drives', 'Playlist • You', 18),
    ('Sunday Slow Mornings', 'Playlist • You', 24),
    ('Gym: Heavy Rotation', 'Playlist • You', 31),
    ('Coding Focus — Deep Work Beats Without Lyrics', 'Playlist • You', 52),
    ('Road Trip 2025', 'Playlist • You', 40),
    ('Rainy Day Jazz', 'Playlist • You', 15),
    ('Kitchen Disco', 'Playlist • You', 27),
    ('Old Favourites', 'Playlist • You', 63),
    ('Summer in Lisbon', 'Playlist • You', 22),
    ('Sleep Sounds', 'Playlist • You', 12),
  ];

  static String playlistId(String title) =>
      'PLriff${_slug(title).replaceAll('-', '')}';

  static Playlist userPlaylist(int i) {
    final (title, description, count) = _playlists[i % _playlists.length];
    return Playlist(
      title: title,
      playlistId: playlistId(title),
      thumbnailUrl:
          i % 4 == 3 ? Playlist.thumbPlaceholderUrl : coverUrl('pl $title'),
      description: description,
      songCount: '$count',
      isCloudPlaylist: false,
    );
  }

  static List<Playlist> get userPlaylists =>
      [for (var i = 0; i < _playlists.length; i++) userPlaylist(i)];

  /// Songs of a user playlist (offset so playlists differ).
  static List<MediaItem> userPlaylistSongs(int i, {int count = 18}) =>
      [for (var n = 0; n < count; n++) song((i * 7 + n * 3) % _songs.length)];

  static const _ytPlaylists = <(String, String)>[
    ('Today\'s Indie Mix', 'Playlist • YouTube Music'),
    ('Chill Hits', 'Playlist • YouTube Music'),
    ('Fresh Finds: Electronic', 'Playlist • YouTube Music'),
    ('Coffeehouse Acoustic', 'Playlist • YouTube Music'),
    (
      'Throwback Thursday Anthems from the Early 2000s',
      'Playlist • 2.1M views'
    ),
    ('Latin Heat', 'Playlist • YouTube Music'),
    ('Lo-fi Study Session', 'Playlist • 4.8M views'),
    ('Golden Era Soul', 'Playlist • YouTube Music'),
    ('Night Run', 'Playlist • YouTube Music'),
    ('Rainforest Ambience', 'Playlist • 860K views'),
  ];

  static Playlist ytPlaylist(int i) {
    final (title, description) = _ytPlaylists[i % _ytPlaylists.length];
    return Playlist(
      title: title,
      playlistId: 'VLRDCLAKriff${_slug(title).replaceAll('-', '')}',
      thumbnailUrl: coverUrl('yt $title'),
      description: description,
    );
  }

  static List<Playlist> get ytPlaylists =>
      [for (var i = 0; i < _ytPlaylists.length; i++) ytPlaylist(i)];

  // ──────────────────────────────────────────────────── daily mixes ──

  static List<GeneratedMix> get dailyMixes => [
        for (final (i, (title, reason)) in const [
          ('Daily Mix 1', 'Nova Hart, Odd Weather and more'),
          ('Daily Mix 2', 'Kaito Moriyama, Priya Raman and more'),
          ('Daily Mix 3', 'Marisol Vega, Los Hermanos del Sur and more'),
          ('Fresh Finds', 'New songs picked for you'),
          ('Release Radar', 'Out this week from artists you follow'),
          ('Rediscover', 'Songs you loved last year'),
        ].indexed)
          GeneratedMix(
            id: 'mix$i',
            title: title,
            reason: reason,
            kind: MixKind.dailyMix,
            tracks: [for (var n = 0; n < 8; n++) songJson(30 + i * 5 + n)],
            generatedTs: DateTime.now().millisecondsSinceEpoch,
          ),
      ];
}
