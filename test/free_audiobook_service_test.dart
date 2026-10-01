import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_item_extras.dart';
import 'package:harmonymusic/services/audiobook_progress_service.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';

/// Shape of `archive.org/advancedsearch.php?...&output=json`.
final _search = <String, dynamic>{
  'responseHeader': {'status': 0},
  'response': {
    'numFound': 3,
    'start': 0,
    'docs': [
      {
        'identifier': 'adventures_holmes_0711_librivox',
        'title': 'The Adventures of Sherlock Holmes (version 2)',
        'creator': 'Arthur Conan Doyle',
        'downloads': 912345,
      },
      {
        // creator as a list, no downloads
        'identifier': 'pride_prejudice_librivox',
        'title': 'Pride and Prejudice',
        'creator': ['Jane Austen', 'LibriVox'],
      },
      {'identifier': 'no_title_item'},
      {
        'identifier': 'adventures_holmes_0711_librivox',
        'title': 'duplicate',
      },
    ],
  },
};

/// Shape of `archive.org/metadata/<id>` for a LibriVox item.
final _metadata = <String, dynamic>{
  'metadata': {
    'identifier': 'adventures_holmes_0711_librivox',
    'title': 'The Adventures of Sherlock Holmes (Version 2)',
    'creator': 'Arthur Conan Doyle',
    'description':
        '<p>Twelve stories featuring Holmes &amp; Watson.<br />Read by volunteers.</p><p>Second paragraph.</p>',
    'subject': 'librivox; audiobooks; mystery; detective',
    'language': 'English',
  },
  'item': {'downloads': 912345},
  'files': [
    {
      'name': 'adventuresholmes_02_doyle_128kb.mp3',
      'format': '128Kbps MP3',
      'track': '02',
      'length': '2400.10',
      'title': 'A Red-Headed League',
    },
    {
      'name': 'adventuresholmes_02_doyle_64kb.mp3',
      'format': '64Kbps MP3',
      'track': '02',
      'length': '40:00',
      'title': 'A Red-Headed League',
    },
    {
      'name': 'adventuresholmes_01_doyle_64kb.mp3',
      'format': '64Kbps MP3',
      'track': '01',
      'length': '3040.39',
      'title': 'A Scandal in Bohemia',
    },
    {
      'name': 'adventuresholmes_10_doyle_64kb.mp3',
      'format': '64Kbps MP3',
      'track': '10/12',
      'length': '1:02:03',
    },
    {'name': 'holmes_1107.jpg', 'format': 'JPEG'},
  ],
};

void main() {
  group('query building', () {
    test('base query is the LibriVox collection', () {
      expect(FreeAudiobookService.buildQuery(),
          'collection:librivoxaudio AND mediatype:audio');
    });

    test('user text is stripped of query syntax', () {
      final q = FreeAudiobookService.buildQuery(text: 'holmes* OR (x:"y")');
      expect(q, contains('(title:(holmes OR x y) OR creator:(holmes OR x y))'));
      expect(FreeAudiobookService.sanitizeTerms('  Jules   Verne! '),
          'Jules Verne');
      expect(FreeAudiobookService.sanitizeTerms('Émile Zola'), 'Émile Zola');
    });

    test('genre adds a subject clause', () {
      expect(FreeAudiobookService.buildQuery(subject: 'science fiction'),
          endsWith('AND subject:"science fiction"'));
    });

    test('search uri asks for popular-first json', () {
      final uri = FreeAudiobookService.searchUri(text: 'dracula', rows: 5);
      expect(uri.host, 'archive.org');
      expect(uri.path, '/advancedsearch.php');
      expect(uri.queryParametersAll['fl[]'],
          ['identifier', 'title', 'creator', 'downloads']);
      expect(uri.queryParameters['sort[]'], 'downloads desc');
      expect(uri.queryParameters['rows'], '5');
      expect(uri.queryParameters['output'], 'json');
    });

    test('blank search does not hit the network', () async {
      expect(await FreeAudiobookService.search('  ?! '), isEmpty);
    });
  });

  group('parseSearch', () {
    test('maps docs, cleans titles, drops bad and duplicate rows', () {
      final books = FreeAudiobookService.parseSearch(_search);
      expect(books.map((b) => b.id), [
        'adventures_holmes_0711_librivox',
        'pride_prejudice_librivox',
      ]);
      expect(books[0].title, 'The Adventures of Sherlock Holmes');
      expect(books[0].downloads, 912345);
      expect(books[1].author, 'Jane Austen');
      expect(books[1].downloads, 0);
      expect(books[0].cover,
          'https://archive.org/services/img/adventures_holmes_0711_librivox');
    });

    test('tolerates garbage', () {
      expect(FreeAudiobookService.parseSearch(null), isEmpty);
      expect(FreeAudiobookService.parseSearch({'response': 'x'}), isEmpty);
    });

    test('json round trip', () {
      final b = FreeAudiobookService.parseSearch(_search).first;
      final back = FreeAudiobook.fromJson(b.toJson());
      expect(back.id, b.id);
      expect(back.title, b.title);
      expect(back.author, b.author);
      expect(back.downloads, b.downloads);
    });
  });

  group('parseMetadata', () {
    final d = FreeAudiobookService.parseMetadata(_metadata)!;

    test('picks one MP3 flavour, in track order', () {
      expect(d.chapters.map((c) => c.title), [
        'A Scandal in Bohemia',
        'A Red-Headed League',
        'adventuresholmes 10 doyle 64kb',
      ]);
      expect(d.chapters.map((c) => c.index), [0, 1, 2]);
      expect(d.chapters.every((c) => c.url.endsWith('_64kb.mp3')), isTrue);
      expect(d.chapters.first.url,
          'https://archive.org/download/adventures_holmes_0711_librivox/adventuresholmes_01_doyle_64kb.mp3');
    });

    test('reads every length format', () {
      expect(d.chapters.map((c) => c.durationSec),
          [closeTo(3040.39, 0.001), 2400, 3723]);
      expect(d.totalSec, closeTo(3040.39 + 2400 + 3723, 0.001));
    });

    test('book fields, subjects and plain-text description', () {
      expect(d.book.title, 'The Adventures of Sherlock Holmes');
      expect(d.book.author, 'Arthur Conan Doyle');
      expect(d.book.downloads, 912345);
      expect(d.subjects, ['mystery', 'detective']);
      expect(d.language, 'English');
      expect(d.description,
          'Twelve stories featuring Holmes & Watson.\nRead by volunteers.\n\nSecond paragraph.');
    });

    test('falls back to any .mp3 when formats are unknown', () {
      final m = FreeAudiobookService.parseMetadata({
        'metadata': {'identifier': 'x', 'title': 'X'},
        'files': [
          {'name': 'b.mp3'},
          {'name': 'a.MP3'},
          {'name': 'cover.jpg'},
        ],
      })!;
      expect(m.chapters.map((c) => c.title), ['a', 'b']);
    });

    test('null without metadata', () {
      expect(FreeAudiobookService.parseMetadata(null), isNull);
      expect(FreeAudiobookService.parseMetadata({'files': []}), isNull);
    });
  });

  test('parseLength', () {
    expect(FreeAudiobookService.parseLength(''), 0);
    expect(FreeAudiobookService.parseLength('12.5'), 12.5);
    expect(FreeAudiobookService.parseLength('02:03'), 123);
    expect(FreeAudiobookService.parseLength('1:00:00'), 3600);
    expect(FreeAudiobookService.parseLength('a:b'), 0);
  });

  group('media items', () {
    final d = FreeAudiobookService.parseMetadata(_metadata)!;
    final items = FreeAudiobookService.toMediaItems(d);

    test('one lv_ item per chapter carrying its own url', () {
      expect(items.length, 3);
      expect(items.first.id, 'lv_adventures_holmes_0711_librivox_0');
      expect(items.first.extrasUrl, d.chapters.first.url);
      expect(items.first.album, 'The Adventures of Sherlock Holmes');
      expect(items.first.duration!.inSeconds, 3040);
      expect(items.first.extras!['audiobookTrackCount'], 3);
    });

    test('recognised as audiobook, not Audiobookshelf', () {
      expect(items.first.isFreeAudiobook, isTrue);
      expect(items.first.isAudiobook, isTrue);
      expect(items.first.isAudiobookshelf, isFalse);
      expect(AudiobookProgressService.isAudiobookItem(items.first), isTrue);
    });

    test('book id comes from extras even with underscores in it', () {
      expect(AudiobookProgressService.bookIdOf(items[2]),
          'adventures_holmes_0711_librivox');
    });
  });

  test('latestPerBook keeps the newest record per book', () {
    final rows = [
      {'id': 'lv_a_3', 'bookId': 'a', 'updatedAt': 30},
      {'id': 'lv_b_0', 'bookId': 'b', 'updatedAt': 20},
      {'id': 'lv_a_1', 'bookId': 'a', 'updatedAt': 10},
      {'id': 'lv_c_0', 'bookId': null, 'updatedAt': 5},
    ];
    expect(AudiobookProgressService.latestPerBook(rows).map((r) => r['id']),
        ['lv_a_3', 'lv_b_0']);
  });
}
