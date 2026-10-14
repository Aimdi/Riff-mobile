import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/app_shortcuts.dart';
import 'package:harmonymusic/services/new_episode_alerts.dart';
import 'package:harmonymusic/services/podcast_service.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_library_ui.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_settings_screen.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  final sent = <Map<Object?, Object?>>[];
  var asked = 0;
  // PermissionStatus.granted; 0 is denied.
  var answer = 1;

  setUp(() async {
    Get.addTranslations(Languages().keys);
    Get.locale = const Locale('en');
    await Hive.openBox('AppPrefs', bytes: Uint8List(0));
    await Hive.openBox('PodcastSubs', bytes: Uint8List(0));
    sent.clear();
    asked = 0;
    answer = 1;
    messenger.setMockMethodCallHandler(NewEpisodeAlerts.channel, (call) async {
      if (call.method == 'set') sent.add(call.arguments as Map);
      return true;
    });
    messenger.setMockMethodCallHandler(permissions, (call) async {
      if (call.method == 'requestPermissions') asked++;
      return {for (final p in call.arguments as List) p: answer};
    });
  });
  tearDown(() async {
    NewEpisodeAlerts.resetForTest();
    messenger.setMockMethodCallHandler(NewEpisodeAlerts.channel, null);
    messenger.setMockMethodCallHandler(permissions, null);
    await Hive.close();
  });

  Future<void> follow(String feed, String title) => PodcastService.subscribe(
      {'feedUrl': feed, 'title': title, 'artwork': 'https://a.example/$title'});

  test('the shows looked at: those followed by a web feed', () {
    expect(
        alertShows([
          {
            'feedUrl': 'https://feeds.example/show',
            'title': 'Show',
            'artwork': 'https://a.example/art.jpg',
          },
          {'feedUrl': 'http://old.example/rss', 'title': null},
          {'feedUrl': 'yt:PL123', 'title': 'From YouTube'},
          {'title': 'No feed'},
        ]),
        [
          {
            'feed': 'https://feeds.example/show',
            'title': 'Show',
            'art': 'https://a.example/art.jpg',
          },
          {'feed': 'http://old.example/rss', 'title': '', 'art': ''},
        ]);
  });

  test('a show left out is not looked at', () {
    final subs = [
      {'feedUrl': 'https://feeds.example/a', 'title': 'A'},
      {'feedUrl': 'https://feeds.example/b', 'title': 'B'},
    ];
    expect(
        alertShows(subs, muted: {'https://feeds.example/a'})
            .map((s) => s['feed']),
        ['https://feeds.example/b']);
  });

  test('leaving a show out (and letting it back in) tells Android', () async {
    await follow('https://feeds.example/a', 'Show A');
    await follow('https://feeds.example/b', 'Show B');
    await NewEpisodeAlerts.setEnabled(true);
    List<Object?> feeds() =>
        (sent.last['shows'] as List).map((s) => (s as Map)['feed']).toList();
    expect(feeds(), ['https://feeds.example/a', 'https://feeds.example/b']);

    await NewEpisodeAlerts.setNotifiesFor('https://feeds.example/a', false);
    expect(NewEpisodeAlerts.notifiesFor('https://feeds.example/a'), isFalse);
    expect(feeds(), ['https://feeds.example/b']);
    expect(Hive.box('AppPrefs').get(NewEpisodeAlerts.mutedKey),
        ['https://feeds.example/a']);

    // Already left out: nothing to tell.
    final told = sent.length;
    await NewEpisodeAlerts.setNotifiesFor('https://feeds.example/a', false);
    expect(sent, hasLength(told));

    await NewEpisodeAlerts.setNotifiesFor('https://feeds.example/a', true);
    expect(NewEpisodeAlerts.notifiesFor('https://feeds.example/a'), isTrue);
    expect(feeds(), ['https://feeds.example/a', 'https://feeds.example/b']);
  });

  test('a notification opens the Inbox, and no other link does', () {
    // The address EpisodeAlerts.kt puts on its notifications.
    expect('${NewEpisodeAlerts.inboxLink}', 'riff://podcasts/inbox');
    expect(NewEpisodeAlerts.opensInbox(NewEpisodeAlerts.inboxLink), isTrue);
    expect(NewEpisodeAlerts.opensInbox(AppShortcut.search.uri), isFalse);
    expect(
        NewEpisodeAlerts.opensInbox(Uri.parse('riff://voice?q=news')), isFalse);
    expect(
        NewEpisodeAlerts.opensInbox(
            Uri.parse('https://music.youtube.com/podcasts/inbox')),
        isFalse);
  });

  test('switched on: asks to notify, then Android gets the shows followed',
      () async {
    await follow('https://feeds.example/a', 'Show A');
    expect(await NewEpisodeAlerts.setEnabled(true), isTrue);
    expect(asked, 1);
    expect(NewEpisodeAlerts.enabled.value, isTrue);
    expect(Hive.box('AppPrefs').get(NewEpisodeAlerts.prefKey), isTrue);
    expect(sent.single, {
      'on': true,
      'shows': [
        {
          'feed': 'https://feeds.example/a',
          'title': 'Show A',
          'art': 'https://a.example/Show A',
        },
      ],
      'channel': 'New episodes',
      'count': '@count new episodes',
    });

    // Off: Android stops looking. Nothing to ask for.
    expect(await NewEpisodeAlerts.setEnabled(false), isTrue);
    expect(asked, 1);
    expect(sent.last['on'], isFalse);
    expect(Hive.box('AppPrefs').get(NewEpisodeAlerts.prefKey), isFalse);
  });

  test('permission refused: it stays off', () async {
    answer = 0;
    expect(await NewEpisodeAlerts.setEnabled(true), isFalse);
    expect(NewEpisodeAlerts.enabled.value, isFalse);
    expect(Hive.box('AppPrefs').get(NewEpisodeAlerts.prefKey), isNull);
    expect(sent, isEmpty);
  });

  test('on: following and unfollowing a show tells Android', () async {
    await Hive.box('AppPrefs').put(NewEpisodeAlerts.prefKey, true);
    await NewEpisodeAlerts.start();
    expect(NewEpisodeAlerts.enabled.value, isTrue);
    expect(sent.single['shows'], isEmpty);

    await follow('https://feeds.example/b', 'Show B');
    await pumpEventQueue();
    expect(
        (sent.last['shows'] as List).single['feed'], 'https://feeds.example/b');

    await PodcastService.unsubscribe('https://feeds.example/b');
    await pumpEventQueue();
    expect(sent.last['shows'], isEmpty);
    expect(sent, hasLength(3));
  });

  test('off: Android hears nothing, followed shows or not', () async {
    await NewEpisodeAlerts.start();
    await follow('https://feeds.example/c', 'Show C');
    await pumpEventQueue();
    await NewEpisodeAlerts.sync();
    expect(sent, isEmpty);
  });

  test('only on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await Hive.box('AppPrefs').put(NewEpisodeAlerts.prefKey, true);
    expect(NewEpisodeAlerts.available, isFalse);
    await NewEpisodeAlerts.start();
    expect(NewEpisodeAlerts.enabled.value, isFalse);
    expect(sent, isEmpty);
  });

  group('the switch in Podcast settings', () {
    Future<void> pumpSetting(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: NewEpisodeAlertsSetting()),
        ));

    /// Lets the permission, the prefs and the channel answer.
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    bool switchedOn(WidgetTester tester) =>
        tester.widget<Switch>(find.byType(Switch)).value;

    testWidgets('on once Android may notify, and off again', (tester) async {
      await pumpSetting(tester);
      expect(find.text('Notify me about new episodes'), findsOneWidget);
      expect(switchedOn(tester), isFalse);

      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(asked, 1);
      expect(switchedOn(tester), isTrue);
      expect(sent.last['on'], isTrue);

      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(switchedOn(tester), isFalse);
      expect(sent.last['on'], isFalse);
    });

    testWidgets("refused: stays off, and says where it's allowed",
        (tester) async {
      answer = 0;
      await pumpSetting(tester);
      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(switchedOn(tester), isFalse);
      expect(sent, isEmpty);
      expect(
          find.text("Allow Riff's notifications in your phone's settings to "
              'hear about new episodes.'),
          findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group("a show's own switch, in its Episodes and downloads sheet", () {
    const feed = 'https://feeds.example/show';

    Future<void> pumpSheet(WidgetTester tester) =>
        tester.pumpWidget(MaterialApp(
          theme: RiffTheme.dark(const Color(0xFF1DB954)),
          home: const Scaffold(body: ShowAlertsSetting(feed: feed)),
        ));

    bool switchedOn(WidgetTester tester) =>
        tester.widget<Switch>(find.byType(Switch)).value;

    testWidgets('only while notifications are on, for a show followed',
        (tester) async {
      await tester.runAsync(() => follow(feed, 'The Show'));
      await pumpSheet(tester);
      expect(find.byType(Switch), findsNothing);

      NewEpisodeAlerts.enabled.value = true;
      await tester.pump();
      expect(find.text('Notify me about new episodes'), findsOneWidget);
      expect(find.text('A notification when this show puts out an episode'),
          findsOneWidget);
      expect(switchedOn(tester), isTrue);

      await tester.runAsync(() => PodcastService.unsubscribe(feed));
      await tester.pump();
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('off: the show is left out, and Android told', (tester) async {
      await tester.runAsync(() => follow(feed, 'The Show'));
      NewEpisodeAlerts.enabled.value = true;
      await pumpSheet(tester);
      await tester.tap(find.byType(Switch));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(switchedOn(tester), isFalse);
      expect(NewEpisodeAlerts.notifiesFor(feed), isFalse);
      expect(sent.last['shows'], isEmpty);
    });
  });
}
