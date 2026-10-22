// Screenshot harness: renders the app's real screens with sample data and
// writes them to test_shots/out/<scenario>_<device>.png.
//
//   flutter test --update-goldens test_shots/
//
// Not part of CI (`flutter test` only scans test/). See test_shots/README.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/library_view_mode.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/screens/Artists/artist_screen.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_detail_screen.dart';
import 'package:harmonymusic/ui/screens/Audiobooks/audiobook_widgets.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen.dart';
import 'package:harmonymusic/ui/screens/Home/home_screen_controller.dart';
import 'package:harmonymusic/ui/widgets/side_nav_bar.dart';

import 'src/harness.dart';
import 'src/media_data.dart';
import 'src/sample_data.dart';

/// One screen to capture: [arrange] pumps the app and gets the screen
/// into the state shown; it runs once per device in [devices].
class Scenario {
  const Scenario(this.name, this.devices, this.arrange);
  final String name;
  final List<ShotDevice> devices;
  final Future<void> Function(WidgetTester tester, ShotDevice device) arrange;
}

/// Every scenario is taken on all three: phone, small phone, tablet.
const _all = [phone, smallPhone, tablet];

final scenarios = <Scenario>[
  // ── Home ─────────────────────────────────────────────────────────────
  Scenario('home', _all, (t, d) => openApp(t)),
  // Every section in one image: the surface grows to the feed's height.
  Scenario('home_full', _all, (t, d) async {
    await openApp(t);
    await growToFeed(t, d);
  }),
  Scenario('discover', _all, (t, d) => openApp(t, tab: RailTab.discover)),

  // ── Library ──────────────────────────────────────────────────────────
  Scenario('library_songs', _all, (t, d) => openApp(t, tab: RailTab.songs)),
  Scenario('library_playlists_grid', _all,
      (t, d) => openApp(t, tab: RailTab.playlists)),
  Scenario('library_playlists_list', _all, (t, d) async {
    await LibraryViewMode.setList(true);
    await openApp(t, tab: RailTab.playlists);
  }),
  Scenario('library_albums', _all, (t, d) => openApp(t, tab: RailTab.albums)),
  Scenario('library_artists', _all, (t, d) => openApp(t, tab: RailTab.artists)),

  // ── Podcasts: each section pill, then a show's page ──────────────────
  Scenario('podcasts_inbox', _all, (t, d) => openApp(t, tab: RailTab.podcasts)),
  for (final (name, labelKey) in const [
    ('podcasts_queue', 'queue'),
    ('podcasts_subscriptions', 'subscriptions'),
    ('podcasts_downloads', 'downloads'),
    ('podcasts_starred', 'starred'),
    ('podcasts_history', 'listeningHistory'),
  ])
    Scenario(name, _all, (t, d) async {
      await openApp(t, tab: RailTab.podcasts);
      await tapPill(t, labelKey.tr);
    }),
  Scenario('podcast_show', _all, (t, d) async {
    await openApp(t, tab: RailTab.podcasts);
    final show = ShotPods.ytShow(0);
    await push(t, ScreenNavigationSetup.playlistScreen,
        [show, show.playlistId, false]);
  }),

  // ── Audiobooks: Library (a server), Discover, Saved; book pages ──────
  Scenario('audiobooks_library', _all,
      (t, d) => openApp(t, tab: RailTab.audiobooks)),
  Scenario('audiobooks_discover', _all, (t, d) async {
    await openApp(t, tab: RailTab.audiobooks);
    await tapPill(t, 'discover'.tr);
  }),
  Scenario('audiobooks_saved', _all, (t, d) async {
    await openApp(t, tab: RailTab.audiobooks);
    await tapPill(t, 'saved'.tr);
  }),
  Scenario('audiobook_free_book', _all, (t, d) async {
    await openApp(t, tab: RailTab.audiobooks);
    openFreeAudiobook(ShotBooks.free[0]);
    await settle(t);
  }),
  Scenario('audiobook_server_book', _all, (t, d) async {
    await openApp(t, tab: RailTab.audiobooks);
    Get.to(() => AudiobookDetailScreen(bookId: ShotBooks.absBooks[0].id),
        transition: Transition.rightToLeft);
    await settle(t);
  }),

  // ── Album and playlist pages ─────────────────────────────────────────
  Scenario('album', _all, (t, d) async {
    await openApp(t);
    final album = ShotData.album(5);
    await push(t, ScreenNavigationSetup.albumScreen, (album, album.browseId));
  }),
  Scenario('playlist', _all, (t, d) async {
    await openApp(t, tab: RailTab.playlists);
    final playlist = ShotData.userPlaylist(0);
    await push(t, ScreenNavigationSetup.playlistScreen,
        [playlist, playlist.playlistId, false]);
  }),
  Scenario('playlist_youtube', _all, (t, d) async {
    await openApp(t);
    final playlist = ShotData.ytPlaylist(1);
    await push(t, ScreenNavigationSetup.playlistScreen,
        [playlist, playlist.playlistId, false]);
  }),

  // ── Artist page ──────────────────────────────────────────────────────
  Scenario('artist', _all, (t, d) async {
    await openApp(t, tab: RailTab.artists);
    await push(t, ScreenNavigationSetup.artistScreen,
        [true, ShotData.artists[0].browseId]);
  }),
  Scenario('artist_full', _all, (t, d) async {
    await openApp(t, tab: RailTab.artists);
    await push(t, ScreenNavigationSetup.artistScreen,
        [true, ShotData.artists[0].browseId]);
    await growToFeed(t, d, within: find.byType(ArtistScreen));
  }),

  // ── Full player ──────────────────────────────────────────────────────
  Scenario('player', _all, (t, d) async {
    await openApp(t);
    Get.find<PlayerController>().playerPanelController.open();
    await settle(t);
  }),

  // ── Search: history, suggestions while typing, results ───────────────
  Scenario('search', _all, (t, d) async {
    await openApp(t, tab: RailTab.discover);
    await push(t, ScreenNavigationSetup.searchScreen);
  }),
  Scenario('search_suggestions', _all, (t, d) async {
    await openApp(t, tab: RailTab.discover);
    await push(t, ScreenNavigationSetup.searchScreen);
    await t.enterText(find.byType(TextField).first, 'nova');
    await settle(t);
  }),
  Scenario('search_results', _all, (t, d) async {
    await openApp(t, tab: RailTab.discover);
    await push(t, ScreenNavigationSetup.searchResultScreen, 'nova hart');
  }),
];

void main() {
  setUpAll(setUpShots);
  tearDownAll(tearDownShots);
  setUp(setUpScenario);
  tearDown(tearDownScenario);

  // One test per scenario and device: a failure stops only that shot.
  for (final s in scenarios) {
    for (final device in s.devices) {
      final name = '${s.name}_${device.name}';
      testWidgets(name, (tester) async {
        await runShot(tester, name, device, () => s.arrange(tester, device));
      });
    }
  }
}

// ── Helpers for arranging a screen ─────────────────────────────────────

/// Pumps the whole app (rail, [tab], mini player) and lets it load. The
/// tab is opened by tapping its rail item, as a user does (the wide rail
/// keeps its own selection, so setting the tab index alone wouldn't show
/// it picked).
Future<void> openApp(WidgetTester tester, {int tab = RailTab.home}) async {
  await tester.pumpWidget(shotHome());
  await settle(tester);
  await precacheAssetImages(tester);
  if (tab == RailTab.home) return;
  Finder railText(String key) =>
      find.descendant(of: find.byType(SideNavBar), matching: find.text(key.tr));
  const labels = {
    RailTab.discover: 'discoverTab',
    RailTab.songs: 'songs',
    RailTab.podcasts: 'podcasts',
    RailTab.audiobooks: 'audiobooks',
    RailTab.playlists: 'playlists',
    RailTab.albums: 'albums',
    RailTab.artists: 'artists',
  };
  final item = railText(labels[tab]!);
  // Playlists / Albums / Artists sit under Songs on the phone rail: open
  // it first, as reaching them does.
  final caret = find.descendant(
      of: find.byType(SideNavBar),
      matching: find.byIcon(Icons.keyboard_arrow_down_rounded));
  const underSongs = [RailTab.playlists, RailTab.albums, RailTab.artists];
  if (underSongs.contains(tab) && caret.evaluate().isNotEmpty) {
    await tester.tap(caret.first);
    await settle(tester, total: const Duration(milliseconds: 600));
  }
  // The phone rail's item is an InkWell around the glyph and its rotated
  // label: its own onTap runs (what a tap does, without hit-testing an
  // accordion that may still be opening). The wide rail's label is tapped.
  // On a rail too short for it, the item is scrolled up into view first
  // (only then: an item already in view stays put).
  await Scrollable.ensureVisible(tester.element(item.first),
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
  await tester.pump();
  final ink = find.ancestor(of: item.first, matching: find.byType(InkWell));
  final onTap =
      ink.evaluate().isEmpty ? null : tester.widget<InkWell>(ink.first).onTap;
  if (onTap != null) {
    onTap();
  } else {
    await tester.tap(item.first);
  }
  await settle(tester);
}

/// Decodes the asset images on screen (the wide rail's logo) for real:
/// asset decoding doesn't advance in a widget test's fake time, so they
/// would show or not depending on timing.
Future<void> precacheAssetImages(WidgetTester tester) async {
  final images = tester
      .widgetList<Image>(find.byType(Image))
      .map((i) => i.image)
      .where((p) => p is AssetImage || p is ExactAssetImage)
      .toSet();
  if (images.isEmpty) return;
  final context = tester.element(find.byType(SideNavBar).first);
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image, context);
    }
  });
  await tester.pump();
}

/// Opens [route] on the app's page navigator, as Get.toNamed does from a
/// tap.
Future<void> push(WidgetTester tester, String route,
    [Object? arguments]) async {
  Get.toNamed(route, id: ScreenNavigationSetup.id, arguments: arguments);
  await settle(tester);
}

/// Taps the section pill (Podcasts, Audiobooks) labelled [label] (a count
/// may follow it, as Queue's does), scrolling the pill strip to it first
/// when it's off to the right.
Future<void> tapPill(WidgetTester tester, String label) async {
  final strip = find
      .descendant(
          of: find.byType(Body),
          matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.right))
      .first;
  final name = RegExp('^${RegExp.escape(label)}(\\s+\\d+)?\$');
  final pill = find.descendant(
      of: strip,
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          name.hasMatch(w.data ?? w.textSpan?.toPlainText() ?? '')));
  if (pill.evaluate().isEmpty) {
    await tester.dragUntilVisible(pill, strip, const Offset(-120, 0));
    await settle(tester, total: const Duration(milliseconds: 500));
  }
  await tester.tap(pill.first);
  await settle(tester);
}

/// Makes the surface as tall as the Home feed (or the page [within]), so
/// every section shows.
Future<void> growToFeed(WidgetTester tester, ShotDevice device,
    {Finder? within}) async {
  final lists = find.descendant(
      of: within ?? find.byType(HomeScreen),
      matching: find.byType(Scrollable));
  for (var pass = 0; pass < 3; pass++) {
    var extent = 0.0;
    for (final s in tester.stateList<ScrollableState>(lists)) {
      final p = s.position;
      if (p.axis == Axis.vertical && p.maxScrollExtent > extent) {
        extent = p.maxScrollExtent;
      }
    }
    if (extent < 1) break;
    final size = tester.view.physicalSize / device.dpr;
    tester.view.physicalSize =
        Size(size.width, size.height + extent) * device.dpr;
    await settle(tester);
  }
}
