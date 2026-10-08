import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/podcast_bookmarks.dart';
import 'package:harmonymusic/services/podcast_inbox_cache.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library.dart';
import 'package:harmonymusic/ui/screens/Podcasts/podcasts_library_controller.dart';
import 'package:harmonymusic/ui/screens/Settings/settings_screen_controller.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/utils/get_localization.dart';
import 'package:hive/hive.dart';

class _FakePlayer extends GetxController implements PlayerController {
  @override
  final currentSong = Rxn<MediaItem>();
  @override
  final buttonState = PlayButtonState.paused.obs;
  @override
  final GlobalKey<ScaffoldState> homeScaffoldkey = GlobalKey<ScaffoldState>();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings extends GetxController implements SettingsScreenController {
  @override
  final podcastContinuousPlaybackEnabled = true.obs;
  @override
  final isTransitionAnimationDisabled = true.obs;
  @override
  final slidableActionEnabled = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No YouTube shows followed, so the Inbox loads without the network.
class _FakeLib extends GetxController implements LibraryPodcastsController {
  @override
  String inboxSubsKey = '';
  @override
  List<MediaItem>? inboxEpisodes;
  @override
  final libraryPodcasts = <Playlist>[].obs;
  @override
  final hasSearched = false.obs;
  @override
  List<MediaItem>? freshInbox(String subsKey) => null;
  @override
  void storeInbox(List<MediaItem> episodes, String subsKey) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _filterLabels = [
  'New',
  'In progress',
  'Queued',
  'Downloaded',
  'Bookmarked',
  'Under 20 min',
];

Finder get _menuItems =>
    find.byWidgetPredicate((w) => w is CheckedPopupMenuItem);

/// The menu entry labelled [label] (the chip may carry the same text).
Finder _menuItem(String label) =>
    find.ancestor(of: find.text(label), matching: _menuItems);

bool _checked(WidgetTester tester, String label) =>
    tester.widget<CheckedPopupMenuItem>(_menuItem(label)).checked;

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('riff_inbox_filter_');
    Hive.init(tmp.path);
    for (final b in [
      'PodcastSubs',
      'PodcastProgress',
      'PodcastPlayed',
      'PodcastQueue',
      'PodcastDownloads',
      PodcastBookmarkStore.box,
      PodcastInboxCache.box,
    ]) {
      await Hive.openBox(b);
    }
    // One episode half listened (Continue listening in the plain Inbox).
    await Hive.box('PodcastProgress').put('podcast_half', {
      'id': 'podcast_half',
      'title': 'Halfway episode',
      'artist': 'Some Show',
      'updatedAt': 1,
      'durationMs': 2400000,
      'positionMs': 900000,
      'url': 'https://example.com/half.mp3',
    });
  });

  tearDownAll(() async {
    await Hive.close();
    tmp.deleteSync(recursive: true);
  });

  setUp(() {
    Get.reset();
    Get.put<PlayerController>(_FakePlayer());
    Get.put<SettingsScreenController>(_FakeSettings());
    Get.put<LibraryPodcastsController>(_FakeLib());
    // One episode waiting in Up Next (only the Queued filter lists it here).
    Get.put(PodcastQueueController()).queue.assignAll([
      const MediaItem(
          id: 'podcast_queued',
          title: 'Queued episode',
          artist: 'Other Show',
          extras: {'isPodcast': true}),
    ]);
  });
  tearDown(Get.reset);

  Future<void> pumpPodcasts(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(411, 914)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      translations: Languages(),
      locale: const Locale('en'),
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: const Scaffold(body: PodcastsLibraryWidget()),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Filter the Inbox'));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(_menuItem(label));
    await tester.pumpAndSettle();
  }

  testWidgets('the Inbox has no second chip row; its filters are in a menu',
      (tester) async {
    await pumpPodcasts(tester);

    // One chip row: the sections. The filters aren't on screen any more.
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.textContaining('Queue'), findsOneWidget);
    for (final label in _filterLabels) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(find.text('Halfway episode'), findsOneWidget);
    expect(find.text('Queued episode'), findsNothing);

    // Tapping the selected Inbox chip lists the plain Inbox and every
    // filter, the current one (plain Inbox) checked.
    await openFilters(tester);
    expect(_menuItems, findsNWidgets(1 + _filterLabels.length));
    for (final label in _filterLabels) {
      expect(_checked(tester, label), isFalse, reason: label);
    }
    expect(_checked(tester, 'Inbox'), isTrue);
  });

  testWidgets('choosing a filter names it on the chip and filters the list',
      (tester) async {
    await pumpPodcasts(tester);
    await openFilters(tester);
    await pick(tester, 'Queued');

    expect(_menuItems, findsNothing);
    expect(find.text('Inbox · Queued'), findsOneWidget);
    expect(find.text('QUEUED · 1'), findsOneWidget);
    expect(find.text('Queued episode'), findsOneWidget);
    // Continue listening belongs to the plain Inbox.
    expect(find.text('Halfway episode'), findsNothing);

    // The menu now has Queued checked; Inbox goes back to the plain Inbox.
    await openFilters(tester);
    expect(_checked(tester, 'Queued'), isTrue);
    await pick(tester, 'Inbox');
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Inbox · Queued'), findsNothing);
    expect(find.text('Halfway episode'), findsOneWidget);
    expect(find.text('Queued episode'), findsNothing);
  });

  testWidgets('dismissing the menu keeps the filter', (tester) async {
    await pumpPodcasts(tester);
    await openFilters(tester);
    await pick(tester, 'In progress');
    expect(find.text('Inbox · In progress'), findsOneWidget);

    await openFilters(tester);
    await tester.tapAt(const Offset(400, 900));
    await tester.pumpAndSettle();
    expect(_menuItems, findsNothing);
    expect(find.text('Inbox · In progress'), findsOneWidget);
    expect(find.text('IN PROGRESS · 1'), findsOneWidget);
  });

  testWidgets('tapping Inbox from another section switches back to it',
      (tester) async {
    await pumpPodcasts(tester);
    await openFilters(tester);
    await pick(tester, 'Queued');

    await tester.tap(find.textContaining(RegExp(r'^Queue\b')));
    await tester.pumpAndSettle();
    // Unselected, the Inbox chip looks like the others: no caret, no
    // filter name, no menu tooltip.
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    expect(find.byTooltip('Filter the Inbox'), findsNothing);

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    // Switched, no menu; the last filter still applies.
    expect(_menuItems, findsNothing);
    expect(find.text('Inbox · Queued'), findsOneWidget);
    expect(find.text('QUEUED · 1'), findsOneWidget);
  });
}
