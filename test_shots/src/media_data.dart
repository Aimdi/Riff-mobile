import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/audiobook_catalog_service.dart';
import 'package:harmonymusic/services/audiobookshelf_service.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/widgets/podcast_play.dart';

import 'sample_data.dart';

/// A podcast show and its recent episodes.
class ShotShow {
  const ShotShow(this.title, this.author, this.episodes);
  final String title;
  final String author;

  /// (title, minutes long, days since it came out).
  final List<(String, int, int)> episodes;

  String get slug => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  String get feedUrl => 'https://feeds.riffshot.example/$slug.xml';

  /// Apple-style artwork, as the directory gives it.
  String get artwork =>
      'https://is1-ssl.mzstatic.com/image/thumb/riffshot/$slug/600x600bb.jpg';

  Map<String, dynamic> get subscription => {
        'title': title,
        'author': author,
        'artwork': artwork,
        'feedUrl': feedUrl,
        'subscribedAt': 1700000000000,
      };
}

/// Podcasts: followed shows (RSS), a YouTube Music show, and the
/// episodes the Inbox, Queue, Downloads, History and Starred list.
class ShotPods {
  ShotPods._();

  static const shows = [
    ShotShow('The Long Way Round', 'Harbor Audio', [
      ('Walking the Camino with Nothing but a Notebook', 58, 0),
      ('The Lighthouse Keepers of Newfoundland', 47, 7),
      ('Night Trains Across Europe', 63, 14),
      ('A Year Without Flying', 52, 21),
    ]),
    ShotShow('Signal & Noise', 'Wired Minds Collective', [
      ('Is the Smartphone Era Already Over?', 41, 1),
      ('Inside the Race for Room-Temperature Superconductors', 55, 8),
      ('The Quiet Comeback of Paper', 38, 15),
    ]),
    ShotShow('Kitchen Table Science', 'Dr. Amara Osei', [
      ('Why Bread Rises (and Sometimes Doesn\'t)', 29, 2),
      ('The Chemistry of a Perfect Cup of Coffee', 33, 9),
      ('Fermentation Is Older Than Farming', 31, 16),
    ]),
    ShotShow('History Unwound', 'Thomas Hale', [
      ('The Library of Alexandria: What Really Happened', 72, 3),
      ('Ep. 214 — The Year Without a Summer', 66, 10),
      ('Pirates of the Barbary Coast', 69, 24),
    ]),
    ShotShow('Off the Map: Travel Stories from the Edges of the World',
        'Lena Fischer', [
      ('Ten Days on a Cargo Ship to Iceland', 44, 4),
      ('The Last Nomads of Mongolia', 49, 18),
    ]),
    ShotShow('The Daily Byte', 'Byte Media', [
      ('Thursday: Chips, Courts and a Very Expensive Satellite', 18, 0),
      ('Wednesday: The App Store Shake-Up, Explained', 21, 1),
      ('Tuesday: Why Your Next Car Might Be a Subscription', 19, 2),
    ]),
    ShotShow('Small Business, Big Ideas', 'Rosa Delgado', [
      ('From Farmers Market to 40 Stores', 37, 5),
      ('Pricing Is a Story You Tell', 34, 12),
    ]),
    ShotShow('Night Owl Mysteries', 'Ember Studios', [
      ('The Vanishing at Hollow Creek, Part 1', 46, 6),
      ('The Vanishing at Hollow Creek, Part 2', 51, 13),
    ]),
  ];

  static String episodeId(ShotShow show, int n) =>
      'podcast_riff_${show.slug.replaceAll('-', '')}_$n';

  static Map<String, dynamic> episodeMap(ShotShow show, int n) {
    final (title, minutes, days) = show.episodes[n];
    final at = DateTime.now().subtract(Duration(days: days, hours: 3 + n));
    return {
      'id': episodeId(show, n),
      'title': title,
      'description':
          'In this episode of ${show.title}, ${show.author} digs into '
              '${title.toLowerCase()}. With listener questions, a few '
              'detours and one very good story.',
      'url': 'https://media.riffshot.example/${show.slug}/$n.mp3',
      'artwork': show.artwork,
      'date': PodcastService.formatDay(at),
      'pubDateMs': at.millisecondsSinceEpoch,
      'durationSec': minutes * 60,
      'podcast': show.title,
    };
  }

  static MediaItem episode(ShotShow show, int n) =>
      podcastEpisodeToMediaItem(episodeMap(show, n), show.subscription);

  /// Every followed show's episodes, newest first (what the Inbox merges).
  static List<MediaItem> get inbox {
    final all = [
      for (final s in shows)
        for (var n = 0; n < s.episodes.length; n++) episode(s, n)
    ];
    all.sort((a, b) => (b.extras!['pubDateMs'] as int)
        .compareTo(a.extras!['pubDateMs'] as int));
    return all;
  }

  /// Which subscriptions an Inbox was built from, as the Inbox keys it
  /// (followed YouTube shows and RSS feeds, sorted).
  static String get subsKey => ([
        for (var i = 0; i < 2; i++) 'yt:${ytShow(i).playlistId}',
        for (final s in shows) 'rss:${s.feedUrl}',
      ]..sort())
          .join('|');

  /// (show, episode, fraction heard) for episodes part-way through.
  static List<(ShotShow, int, double)> get inProgress => [
        (shows[1], 0, 0.62),
        (shows[3], 0, 0.27),
        (shows[0], 1, 0.81),
      ];

  static List<(ShotShow, int)> get played => [
        (shows[5], 1),
        (shows[5], 2),
        (shows[2], 1),
      ];

  static List<(ShotShow, int)> get queue => [
        (shows[0], 0),
        (shows[2], 0),
        (shows[4], 0),
        (shows[3], 1),
        (shows[6], 0),
        (shows[7], 0),
      ];

  static List<(ShotShow, int)> get downloads => [
        (shows[0], 0),
        (shows[3], 1),
        (shows[4], 1),
        (shows[7], 1),
      ];

  static List<(ShotShow, int)> get history => [
        (shows[1], 0),
        (shows[3], 0),
        (shows[5], 1),
        (shows[0], 1),
        (shows[2], 1),
        (shows[6], 1),
        (shows[5], 2),
        (shows[1], 2),
      ];

  static List<(ShotShow, int)> get starred => [
        (shows[3], 2),
        (shows[1], 1),
        (shows[4], 1),
        (shows[2], 2),
      ];

  // ────────────────────────────────────── YouTube Music podcast shows ──

  static Playlist ytShow(int i) {
    const titles = [
      ('Deep Cuts with Mara Lin', 'Mara Lin'),
      ('The Practice Room', 'Riverside Music Co.'),
    ];
    final (title, author) = titles[i];
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return Playlist(
      title: title,
      playlistId: 'MPSPPLriff$slug',
      thumbnailUrl: ShotData.coverUrl('ytpod $title'),
      description: author,
      kind: 'podcast',
    );
  }

  /// A YouTube Music show's episodes (what getPlaylistOrAlbumSongs
  /// answers for an MPSP id).
  static List<MediaItem> ytEpisodes(Playlist show) {
    const titles = [
      ('How a Bassline Carries a Whole Song', 54, 1),
      ('Ep. 88: Recording an Album in a Lighthouse', 67, 6),
      ('The Art of the Bridge', 41, 13),
      ('Producers on Their Favourite Mistakes', 72, 20),
      ('Why Some Choruses Get Stuck in Your Head', 38, 27),
      ('Live from the Basement: Three Bands, One Night', 95, 34),
      ('Listener Mailbag: Your Gear Questions Answered', 46, 41),
      ('The Story Behind the Synth Sound of the Eighties', 58, 48),
    ];
    return [
      for (final (n, (title, minutes, days)) in titles.indexed)
        MediaItem(
          id: 'ytpod${show.playlistId.hashCode.abs() % 1000}e$n',
          title: title,
          artist: show.title,
          duration: Duration(minutes: minutes),
          artUri: Uri.parse(show.thumbnailUrl),
          extras: {
            'isPodcast': true,
            'date': PodcastService.formatDay(
                DateTime.now().subtract(Duration(days: days))),
            'pubDateMs': DateTime.now()
                .subtract(Duration(days: days))
                .millisecondsSinceEpoch,
            'description':
                '${show.description} talks with guests about $title.',
          },
        ),
    ];
  }
}

/// Audiobooks: LibriVox (free, playable), Apple's chart (browse only),
/// and an Audiobookshelf server.
class ShotBooks {
  ShotBooks._();

  static const _free = <(String, String, String, int)>[
    ('pride_prejudice_librivox', 'Pride and Prejudice', 'Jane Austen', 1840211),
    (
      'adventures_holmes_librivox',
      'The Adventures of Sherlock Holmes',
      'Arthur Conan Doyle',
      1622480
    ),
    (
      'frankenstein_librivox',
      'Frankenstein; or, The Modern Prometheus',
      'Mary Wollstonecraft Shelley',
      990312
    ),
    ('moby_dick_librivox', 'Moby Dick', 'Herman Melville', 870554),
    ('dracula_librivox', 'Dracula', 'Bram Stoker', 812004),
    ('little_women_librivox', 'Little Women', 'Louisa May Alcott', 755932),
    (
      'count_monte_cristo_librivox',
      'The Count of Monte Cristo',
      'Alexandre Dumas',
      702118
    ),
    ('time_machine_librivox', 'The Time Machine', 'H. G. Wells', 655410),
    (
      'treasure_island_librivox',
      'Treasure Island',
      'Robert Louis Stevenson',
      598201
    ),
    (
      'anne_green_gables_librivox',
      'Anne of Green Gables',
      'Lucy Maud Montgomery',
      571877
    ),
    ('jane_eyre_librivox', 'Jane Eyre', 'Charlotte Brontë', 544306),
    ('war_worlds_librivox', 'The War of the Worlds', 'H. G. Wells', 512993),
  ];

  static List<FreeAudiobook> get free => [
        for (final (id, title, author, downloads) in _free)
          FreeAudiobook(
              id: id, title: title, author: author, downloads: downloads)
      ];

  /// archive.org advancedsearch.php JSON for [free].
  static Map<String, Object> get searchJson => {
        'responseHeader': {'status': 0},
        'response': {
          'numFound': _free.length,
          'start': 0,
          'docs': [
            for (final (id, title, author, downloads) in _free)
              {
                'identifier': id,
                'title': title,
                'creator': author,
                'downloads': downloads,
              }
          ],
        },
      };

  static const chapterTitles = [
    'Chapter 1: It Is a Truth Universally Acknowledged',
    'Chapter 2: Mr. Bennet\'s Visit',
    'Chapter 3: The Assembly at Meryton',
    'Chapter 4: Jane and Elizabeth',
    'Chapter 5: The Lucases',
    'Chapter 6: An Evening at Lucas Lodge',
    'Chapter 7: Jane Rides to Netherfield in the Rain',
    'Chapter 8: At Netherfield',
    'Chapter 9: Mrs. Bennet Calls',
    'Chapter 10: Letters and Music',
    'Chapter 11: A Walk About the Room',
    'Chapter 12: The Sisters Return Home',
  ];

  /// archive.org /metadata JSON for the book [id].
  static Map<String, Object> metadataJson(String id) {
    final book = _free.firstWhere((b) => b.$1 == id, orElse: () => _free[0]);
    return {
      'metadata': {
        'identifier': book.$1,
        'title': book.$2,
        'creator': book.$3,
        'description':
            '<p>One of the best-loved novels in the English language, read '
                'by LibriVox volunteers.</p><p>This recording is in the '
                'public domain.</p>',
        'subject': 'librivox; audiobooks; fiction; romance; classics',
        'language': 'English',
      },
      'item': {'downloads': book.$4},
      'files': [
        for (final (n, title) in chapterTitles.indexed)
          {
            'name': '${book.$1}_${(n + 1).toString().padLeft(2, '0')}_64kb.mp3',
            'format': '64Kbps MP3',
            'track': '${n + 1}',
            'length': '${1300 + n * 97}.4',
            'title': title,
          },
      ],
    };
  }

  /// (title, author, genre) of Apple's chart, made up.
  static const _store = <(String, String, String)>[
    ('The Quiet Orchard', 'Mara Ellison', 'Literary Fiction'),
    ('Tidewater', 'Jonah Price', 'Thrillers'),
    ('A Map of Small Fires', 'Inês Carvalho', 'Literary Fiction'),
    ('The Last Lighthouse Keeper', 'Owen Marsh', 'Historical Fiction'),
    (
      'Everything We Carried: A Memoir of Leaving Home',
      'Hana Kim',
      'Biographies & Memoirs'
    ),
    ('Signal Lost', 'R. J. Ambrose', 'Sci-Fi & Fantasy'),
    ('The Glass Garden', 'Celeste Moreau', 'Romance'),
    ('Northbound', 'Daniel Okoye', 'Mysteries'),
    ('Salt and Ember', 'Freya Lund', 'Sci-Fi & Fantasy'),
    ('The Cartographer\'s Daughter', 'Elena Ruiz', 'Historical Fiction'),
  ];

  static List<AudiobookItem> get store => [
        for (final (i, (title, author, genre)) in _store.indexed)
          AudiobookItem(
            id: '${1600000000 + i}',
            title: title,
            author: author,
            cover: ShotData.coverUrl('book $title'),
            genre: genre,
            description: 'A gripping, beautifully narrated story.',
          ),
      ];

  /// Apple's top-audiobooks RSS JSON for [store].
  static Map<String, Object> get chartJson => {
        'feed': {
          'entry': [
            for (final b in store)
              {
                'id': {
                  'attributes': {'im:id': b.id}
                },
                'im:name': {'label': b.title},
                'im:artist': {'label': b.author},
                'im:image': [
                  {'label': b.cover}
                ],
                'category': {
                  'attributes': {'label': b.genre}
                },
                'summary': {'label': b.description},
              }
          ]
        }
      };

  // ───────────────────────────────────────────────── Audiobookshelf ──

  static const absHost = 'https://books.riffshot.example';

  static final absBooks = [
    for (final (i, (title, author, subtitle, hours, progress)) in const [
      ('Project Hail Mary', 'Andy Weir', null, 16.2, 0.42),
      (
        'The Name of the Wind',
        'Patrick Rothfuss',
        'The Kingkiller Chronicle',
        27.9,
        0.08
      ),
      ('Atomic Habits', 'James Clear', null, 5.6, 1.0),
      ('Circe', 'Madeline Miller', null, 12.1, 0.0),
      (
        'Sapiens: A Brief History of Humankind',
        'Yuval Noah Harari',
        null,
        15.3,
        0.67
      ),
      ('The Hobbit', 'J. R. R. Tolkien', null, 11.1, 0.0),
      ('Educated', 'Tara Westover', null, 12.2, 0.0),
      ('Dune', 'Frank Herbert', 'Dune Chronicles, Book 1', 21.0, 0.15),
      ('The Midnight Library', 'Matt Haig', null, 8.8, 0.0),
      ('Born a Crime', 'Trevor Noah', null, 8.7, 0.0),
    ].indexed)
      AbsBook(
        id: 'li_riff$i',
        title: title,
        author: author,
        subtitle: subtitle,
        duration: hours * 3600,
        progress: progress,
      ),
  ];

  static AbsBookDetail absDetail(String id) {
    final book =
        absBooks.firstWhere((b) => b.id == id, orElse: () => absBooks.first);
    return AbsBookDetail(
      id: book.id,
      title: book.title,
      author: book.author ?? '',
      narrator: 'Ray Porter',
      description:
          'Ryland Grace is the sole survivor on a desperate, last-chance '
          'mission — and if he fails, humanity and the earth itself will '
          'perish. Except that right now, he doesn\'t know that.',
      currentTime: (book.duration ?? 0) * (book.progress ?? 0),
      tracks: [
        for (var n = 0; n < 14; n++)
          AbsAudioTrack(
            index: n,
            title: 'Chapter ${n + 1}',
            contentUrl: '/api/items/${book.id}/file/$n',
            duration: 3600 + n * 143.0,
          ),
      ],
    );
  }
}
