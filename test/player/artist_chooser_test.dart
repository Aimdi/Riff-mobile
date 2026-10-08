import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/player/components/artist_chooser_sheet.dart';
import 'package:harmonymusic/ui/widgets/letter_art.dart';

void main() {
  late Future<String?> Function(String id) realFetch;
  setUp(() {
    realFetch = ArtistPhotos.fetch;
    ArtistPhotos.clear();
  });
  tearDown(() {
    ArtistPhotos.fetch = realFetch;
    ArtistPhotos.clear();
  });

  group('ArtistPhotos', () {
    test('one lookup per artist; hits are kept, misses retried', () async {
      var calls = 0;
      final gate = Completer<String?>();
      ArtistPhotos.fetch = (id) {
        calls++;
        return gate.future;
      };
      final a = ArtistPhotos.of('UC1');
      final b = ArtistPhotos.of('UC1');
      gate.complete('https://x/photo');
      expect(await a, 'https://x/photo');
      expect(await b, 'https://x/photo');
      expect(calls, 1);
      expect(ArtistPhotos.known('UC1'), 'https://x/photo');
      expect(await ArtistPhotos.of('UC1'), 'https://x/photo');
      expect(calls, 1);

      ArtistPhotos.fetch = (id) async {
        calls++;
        throw StateError('offline');
      };
      expect(await ArtistPhotos.of('UC2'), isNull);
      expect(await ArtistPhotos.of('UC2'), isNull);
      expect(calls, 3);
    });
  });

  testWidgets('lists each artist with a letter avatar; a tap picks it',
      (tester) async {
    ArtistPhotos.fetch = (_) async => null;
    final picked = <String>[];
    await tester.pumpWidget(GetMaterialApp(
      translations: _T(),
      locale: const Locale('en'),
      home: Scaffold(
        body: ArtistChooserSheet(
          artists: const [
            (id: 'UCa', name: 'Anyma'),
            (id: 'UCg', name: 'Grimes'),
          ],
          onPick: picked.add,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Choose artist'), findsOneWidget);
    expect(find.text('Anyma'), findsOneWidget);
    expect(find.text('Grimes'), findsOneWidget);
    expect(find.byType(LetterArt), findsNWidgets(2));
    await tester.tap(find.text('Grimes'));
    expect(picked, ['UCg']);
  });

  testWidgets('showArtistChooser closes before opening the pick',
      (tester) async {
    ArtistPhotos.fetch = (_) async => null;
    String? picked;
    await tester.pumpWidget(GetMaterialApp(
      translations: _T(),
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showArtistChooser(
                context,
                const [
                  (id: 'UCa', name: 'Anyma'),
                  (id: 'UCg', name: 'Grimes'),
                ],
                onPick: (id) => picked = id),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Choose artist'), findsOneWidget);
    await tester.tap(find.text('Anyma'));
    await tester.pumpAndSettle();
    expect(picked, 'UCa');
    expect(find.text('Choose artist'), findsNothing);
  });
}

class _T extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en': {'chooseArtist': 'Choose artist'}
      };
}
