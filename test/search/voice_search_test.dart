import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playling_from.dart';
import 'package:harmonymusic/services/discovery/discovery_types.dart';
import 'package:harmonymusic/services/music_service.dart';
import 'package:harmonymusic/services/voice_input.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen.dart';
import 'package:harmonymusic/ui/screens/Search/search_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:hive/hive.dart';

import '../fakes/fake_music_services.dart';

/// Plays the search's top song: what was searched, and the song.
class _FakePlayer extends GetxController implements PlayerController {
  final played = <String>[];

  @override
  Future<bool> playPlayListSong(List<MediaItem> mediaItems, int index,
      {PlaylingFrom? playfrom, DiscoverySource? source}) async {
    played.add('${playfrom?.name}: ${mediaItems[index].title}');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var canListen = true;
  // What the phone hears; null: cancelled.
  String? heard;

  setUp(() {
    VoiceInput.resetForTest();
    calls.clear();
    canListen = true;
    heard = null;
    messenger.setMockMethodCallHandler(VoiceInput.channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'canListen' => canListen,
        'listen' => heard,
        _ => null,
      };
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(VoiceInput.channel, null);
    VoiceInput.resetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  group('VoiceInput', () {
    test('asks the phone once whether it can listen', () async {
      expect(await VoiceInput.available(), isTrue);
      expect(await VoiceInput.available(), isTrue);
      expect(VoiceInput.known, isTrue);
      expect(calls.map((c) => c.method), ['canListen']);
    });

    test('no speech recognition, or not Android: no voice search', () async {
      canListen = false;
      expect(await VoiceInput.available(), isFalse);

      VoiceInput.resetForTest();
      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(await VoiceInput.available(), isFalse);
      expect(calls, isEmpty);
    });

    test('no answer is no answer: asked again next time', () async {
      messenger.setMockMethodCallHandler(VoiceInput.channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'gone');
      });
      expect(await VoiceInput.available(), isFalse);
      expect(VoiceInput.known, isNull);
      expect(await VoiceInput.available(), isFalse);
      expect(calls, hasLength(2));
    });

    test('what it heard, trimmed; nothing when cancelled or blank', () async {
      heard = '  daft punk ';
      expect(await VoiceInput.listen(prompt: 'Say it'), 'daft punk');
      expect(calls.single.arguments, {'prompt': 'Say it'});
      heard = null;
      expect(await VoiceInput.listen(), isNull);
      heard = '  ';
      expect(await VoiceInput.listen(), isNull);
    });
  });

  // Tests run as Android.
  group('the search field mic', () {
    late FakeMusicServices music;
    late _FakePlayer player;

    setUp(() async {
      await Hive.openBox('searchQuery', bytes: Uint8List(0));
      music = Get.put<MusicServices>(FakeMusicServices()) as FakeMusicServices;
      player = Get.put<PlayerController>(_FakePlayer()) as _FakePlayer;
    });
    tearDown(() async {
      Get.reset();
      await Hive.close();
    });

    Widget app() => MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: Navigator(
            key: Get.nestedKey(ScreenNavigationSetup.id),
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  settings.name == ScreenNavigationSetup.searchResultScreen
                      ? Scaffold(body: Text('results: ${settings.arguments}'))
                      : const SearchScreen(),
            ),
          ),
        );

    // Labels show their keys: no translations loaded here.
    final mic = find.byTooltip('voiceSearch');

    testWidgets('what was heard is searched as Enter does: its results open',
        (tester) async {
      heard = 'daft punk';
      await tester.pumpWidget(app());
      await tester.pump();
      expect(mic, findsOneWidget);

      await tester.tap(mic);
      await tester.pump();
      expect(calls.last.method, 'listen');
      expect(calls.last.arguments, {'prompt': 'voiceSearchPrompt'});

      await tester.pumpAndSettle();
      expect(find.text('results: daft punk'), findsOneWidget);
      // Nothing plays until a result is picked.
      expect(player.played, isEmpty);
      expect(music.searches['songs'], isNull);
      expect(Get.find<SearchScreenController>().historyQuerylist.first,
          'daft punk');
    });

    testWidgets('cancelled: nothing searched', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(mic);
      await tester.pump();
      expect(calls.last.method, 'listen');
      expect(music.searches, isEmpty);
      expect(Get.find<SearchScreenController>().historyQuerylist, isEmpty);
    });

    testWidgets('the mic while the field is empty, clear while it is not',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'daft');
      await tester.pump();
      expect(mic, findsNothing);
      expect(find.byTooltip('clear'), findsOneWidget);

      await tester.tap(find.byTooltip('clear'));
      // Back at once, without a blank frame first.
      await tester.pump();
      expect(mic, findsOneWidget);
      // The suggestions' typing pause runs out.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets("a phone that can't listen has no mic", (tester) async {
      canListen = false;
      await tester.pumpWidget(app());
      await tester.pump();
      expect(mic, findsNothing);
    });
  });
}
