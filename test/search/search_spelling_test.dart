import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/search_spelling.dart';
import 'package:harmonymusic/ui/screens/Search/components/search_spelling_line.dart';
import 'package:harmonymusic/ui/screens/Search/search_result_screen_controller.dart';

import '../fakes/fake_music_services.dart';

Map<String, dynamic> _runs(String text) => {
      'runs': [
        {'text': text, 'italics': true}
      ]
    };

/// YouTube Music's "Showing results for beyoncé · Search instead for
/// beyonse", as its search answers it.
Map<String, dynamic> _showingResultsFor() => {
      'itemSectionRenderer': {
        'contents': [
          {
            'showingResultsForRenderer': {
              'showingResultsFor': _runs('Showing results for '),
              'correctedQuery': _runs('beyoncé'),
              'correctedQueryEndpoint': {
                'searchEndpoint': {'query': 'beyoncé'}
              },
              'searchInsteadFor': _runs('Search instead for '),
              'originalQuery': _runs('beyonse'),
              'originalQueryEndpoint': {
                'searchEndpoint': {'query': 'beyonse', 'params': 'QgIIAQ%3D%3D'}
              },
            }
          }
        ]
      }
    };

/// "Did you mean: beyoncé" (the results stay those for the words typed).
Map<String, dynamic> _didYouMean({bool endpoint = true}) => {
      'itemSectionRenderer': {
        'contents': [
          {
            'didYouMeanRenderer': {
              'didYouMean': _runs('Did you mean: '),
              'correctedQuery': {
                'runs': [
                  {'text': 'beyon'},
                  {'text': 'cé', 'italics': true}
                ]
              },
              if (endpoint)
                'correctedQueryEndpoint': {
                  'searchEndpoint': {'query': 'beyoncé'}
                },
            }
          }
        ]
      }
    };

final _songsShelf = {
  'musicShelfRenderer': {
    'title': _runs('Songs'),
    'contents': const [],
  }
};

/// [MusicServices] answering every request with [response], keeping the
/// request bodies in [bodies].
MusicServices _answering(
    Map<String, dynamic> response, List<Map<String, dynamic>> bodies) {
  final ms = MusicServices();
  ms.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    bodies.add(Map<String, dynamic>.from(options.data as Map));
    handler.resolve(
        Response(requestOptions: options, statusCode: 200, data: response));
  }));
  return ms;
}

Map<String, dynamic> _searchResponse(List<Map<String, dynamic>> sections) => {
      'contents': {
        'tabbedSearchResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {'contents': sections}
                }
              }
            }
          ]
        }
      }
    };

/// YouTube Music's spelling help in search, as its search page, Spotify's
/// and Apple Music's show it.
void main() {
  group('what YouTube Music says', () {
    test('results for its words, with the way back to the words typed', () {
      final s =
          SearchSpelling.fromSections([_showingResultsFor(), _songsShelf])!;
      expect(s.applied, isTrue);
      expect(s.corrected, 'beyoncé');
      expect(s.original, 'beyonse');
      expect(s.originalParams, 'QgIIAQ%3D%3D');
    });

    test('a suggestion, by its search or else its words', () {
      var s = SearchSpelling.fromSections([_didYouMean()])!;
      expect(s.applied, isFalse);
      expect(s.corrected, 'beyoncé');
      s = SearchSpelling.fromSections([_didYouMean(endpoint: false)])!;
      expect(s.corrected, 'beyoncé');
      expect(s.original, isNull);
    });

    test('nothing said, or nothing to say', () {
      expect(SearchSpelling.fromSections(null), isNull);
      expect(SearchSpelling.fromSections([_songsShelf]), isNull);
      expect(
          SearchSpelling.fromSections([
            {
              'itemSectionRenderer': {
                'contents': [
                  {'messageRenderer': _runs('No results')}
                ]
              }
            }
          ]),
          isNull);
      // "Showing results for" the very words typed.
      final same = _showingResultsFor();
      ((same['itemSectionRenderer']['contents'] as List).first
              as Map)['showingResultsForRenderer']['correctedQueryEndpoint']
          ['searchEndpoint']['query'] = 'Beyonse';
      expect(SearchSpelling.fromSections([same]), isNull);
    });
  });

  test('the overview search carries it; a tab\'s search doesn\'t', () async {
    final bodies = <Map<String, dynamic>>[];
    final ms = _answering(
        _searchResponse([_showingResultsFor(), _songsShelf]), bodies);

    final all = await ms.search('beyonse');
    final s = all[SearchSpelling.key] as SearchSpelling;
    expect(s.corrected, 'beyoncé');
    expect(all['Songs'], isEmpty);
    // Not a list of results: no tab of its own.
    expect(all[SearchSpelling.key], isNot(isA<List>()));

    final songs = await ms.search('beyonse', filter: 'songs');
    expect(songs.containsKey(SearchSpelling.key), isFalse);

    // The words as typed: YouTube Music's own parameters for them, or
    // the ones that leave spelling alone.
    bodies.clear();
    await ms.search('beyonse', filterParams: 'QgIIAQ%3D%3D');
    await ms.search('beyonse', ignoreSpelling: true);
    expect(bodies.map((b) => b['params']),
        ['QgIIAQ%3D%3D', 'EhGKAQ4IARABGAEgASgAOAFAAUICCAE%3D']);
  });

  group('the results page', () {
    late FakeMusicServices music;
    late SearchResultScreenController c;

    setUp(() {
      Get.reset();
      music = FakeMusicServices();
      Get.put<MusicServices>(music);
      c = SearchResultScreenController();
      c.queryString.value = 'beyonse';
    });
    tearDown(Get.reset);

    /// The overview search pending now answers with [spelling].
    Future<void> answer(Future<void> searching, SearchSpelling? spelling,
        {List<String> songs = const ['song']}) async {
      music.searches[null]!.removeLast().complete({
        if (spelling != null) SearchSpelling.key: spelling,
        'Songs': songs,
        'searchEndpoint': {'Songs': 'chip'},
      });
      await searching;
    }

    test('"Search instead for": the words typed, exactly, in each tab too',
        () async {
      await answer(
          c.retrySearch(),
          const SearchSpelling(
              corrected: 'beyoncé',
              applied: true,
              original: 'beyonse',
              originalParams: 'QgIIAQ%3D%3D'));
      expect(c.spelling?.corrected, 'beyoncé');
      expect(c.railItems, ['Songs']);

      await answer(c.searchOriginal(), null);
      final exact = music.searchCalls.last;
      expect(exact.query, 'beyonse');
      expect(exact.filter, isNull);
      expect(exact.filterParams, 'QgIIAQ%3D%3D');
      expect(c.queryString.value, 'beyonse');
      expect(c.spelling, isNull);

      // The Songs tab leaves spelling alone too (not the chip's params).
      final tab = c.onDestinationSelected(1);
      final songs = music.searchCalls.last;
      expect(songs.filter, 'songs');
      expect(songs.ignoreSpelling, isTrue);
      expect(songs.filterParams, isNull);
      music.searches['songs']!.single.complete({
        'Songs': ['exact song']
      });
      await tab;
      expect(c.separatedResultContent['Songs'], ['exact song']);
    });

    test(
        '"Did you mean": its words searched, as any search; a tab still '
        'loading for the old words stays out', () async {
      await answer(c.retrySearch(),
          const SearchSpelling(corrected: 'beyoncé', applied: false));
      // The Songs tab for "beyonse", slow.
      final oldTab = c.onDestinationSelected(1);
      await c.onDestinationSelected(0);

      final searching = c.searchCorrected();
      expect(c.navigationRailCurrentIndex.value, 0);
      final corrected = music.searchCalls.last;
      expect(corrected.query, 'beyoncé');
      expect(corrected.ignoreSpelling, isFalse);
      expect(corrected.filterParams, isNull);
      await answer(searching, null);
      expect(c.queryString.value, 'beyoncé');

      music.searches['songs']!.single.complete({
        'Songs': ['beyonse song']
      });
      await oldTab;
      expect(c.separatedResultContent.containsKey('Songs'), isFalse);

      // Its own Songs tab: the chip's parameters, as before.
      final tab = c.onDestinationSelected(1);
      expect(music.searchCalls.last.filterParams, 'chip');
      expect(music.searchCalls.last.query, 'beyoncé');
      music.searches['songs']!.last.complete({
        'Songs': ['beyoncé song']
      });
      await tab;
      expect(c.separatedResultContent['Songs'], ['beyoncé song']);
    });
  });

  group('the line above the results', () {
    Future<List<String>> show(WidgetTester tester, SearchSpelling s) async {
      final tapped = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SearchSpellingLine(
            spelling: s,
            searched: 'beyonse',
            onCorrected: () => tapped.add('corrected'),
            onOriginal: () => tapped.add('original'),
          ),
        ),
      ));
      return tapped;
    }

    testWidgets('showing results for its words; search the words typed',
        (tester) async {
      final tapped = await show(
          tester, const SearchSpelling(corrected: 'beyoncé', applied: true));
      expect(find.textContaining('searchShowingResultsFor'), findsOneWidget);
      expect(find.textContaining('beyoncé'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'searchInsteadFor'));
      expect(tapped, ['original']);
    });

    testWidgets('did you mean: its words, a tap away', (tester) async {
      final tapped = await show(
          tester, const SearchSpelling(corrected: 'beyoncé', applied: false));
      expect(find.text('searchDidYouMean'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'beyoncé'));
      expect(tapped, ['corrected']);
    });
  });
}
