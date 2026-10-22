# Screenshot harness

Renders Riff's real screens (Home, Discover, the library, Podcasts,
Audiobooks, album and playlist pages, the full player, Search) as PNGs, with
realistic sample data, without a device, emulator or network. It is a set of
widget tests that pump the app's own widgets and controllers over fake data.

```sh
flutter test --update-goldens test_shots/
```

The PNGs land in `test_shots/out/<scenario>_<device>.png` (ignored by git).
`--update-goldens` is what writes them; without it each test compares against
the PNG already there and fails when the screen has changed, which is a quick
way to see what a change touched.

One scenario at a time: `flutter test --update-goldens test_shots/ --plain-name home_phone`.

The harness lives outside `test/`, so CI (`flutter test --exclude-tags live`)
never runs it.

## Devices

| name    | logical size | PNG size    |
|---------|--------------|-------------|
| `phone` | 411 × 891    | 822 × 1782  |
| `small` | 360 × 780    | 720 × 1560  |
| `tablet`| 900 × 1280   | 1800 × 2560 |
| `large` | 360 × 780    | 720 × 1560  |

All at device pixel ratio 2, with a 28dp status bar and 20dp navigation bar.
`large` is the small phone at the largest font size Riff follows (1.3x).
`home_full_*` grows the surface to the Home feed's full scroll height, so
every section is in one image.

## Options (`--dart-define`)

- `SHOT_ACCENT=Blue` (Violet, Crimson, Amber, Cyan): another accent; files get
  a suffix (`home_phone_blue.png`). Green is the default.
- `SHOT_A11Y=true`: also checks Flutter's accessibility guidelines on each
  screen (48 dp Android tap targets, labelled tap targets, text contrast) and
  writes what falls short to `out/<scenario>_<device>.a11y.txt`.
- `SHOT_STRICT=true`: a scenario that reports a layout overflow or a build
  exception fails. By default it only warns.
- `SHOT_LIVE_MOTION=true`: capture with animations running. By default the
  last frame is drawn with Android's Remove animations on, so marquee titles
  rest (ellipsized) instead of being caught mid-scroll and every run draws the
  same picture.

## Errors

Overflows and build exceptions while a scenario renders are written to
`out/<scenario>_<device>.errors.txt` (and printed as a warning). Image load
noise (palette and pre-cache lookups against hosts that don't exist) is
filtered out. An `.errors.txt` means the screen itself has a problem at that
size: the stripes are in the PNG too.

## How it works

- `src/harness.dart`: devices, the app frame (`GetMaterialApp` as `main.dart`
  builds it: translations, Riff's page timing, the theme from
  `ThemeController`, the text scale), `runShot` (size, real shadows, error
  collection, capture at the device's pixel ratio, timers drained).
- `src/fonts.dart`: loads every font in the test bundle's FontManifest (Inter,
  MaterialIcons, Ionicons) plus Roboto from Flutter's cache, so text and icons
  aren't boxes.
- `src/covers.dart`: cover art. `RiffNetworkImage.debugImageOverride`
  (lib/ui/widgets/image_widget.dart, null in the app) is set to paint a
  gradient with a soft shape, picked from a hash of the URL without its size
  suffix. Every cover in the app goes through `RiffNetworkImage`. The player's
  page colours (`PlayerCoverColors`, `PodcastPlayerTint`) are filled from the
  same colours, as the app would take them from the cover.
- `src/sample_data.dart`, `src/media_data.dart`: the catalogue (songs, albums,
  artists, playlists, mixes; podcast shows and episodes; LibriVox, store and
  Audiobookshelf books).
- `src/env.dart`: every Hive box opened in memory
  (`Hive.openBox(name, bytes: …)`), plugin channels stubbed (paths, secure
  storage, the app's `riff/*` channels), canned HTTP for the audiobook
  catalogues (their `@visibleForTesting` Dio).
- `src/stores.dart`: what's written into the boxes before each scenario
  (preferences, recently played, favourites, downloads, library, stats,
  podcast subscriptions, progress, queue, downloads, history, starred,
  audiobook progress and saves, search history, the Spotify shelves cache).
- `src/fakes.dart`: the app's own controllers with their start-up work (audio
  service, network, file system) left out of `onInit`, so the screens read
  their real fields: `PlayerController` (a song playing from a queue),
  `HomeScreenController` (the YouTube Music feed), `SettingsScreenController`,
  the library and podcast controllers, `DiscoveryService` (mixes),
  `AudiobookshelfService` (a signed-in server), and `MusicServices` answering
  album, playlist, podcast and search requests from the sample data. The rest
  of `main.dart`'s services are the real ones.

Each scenario/device pair is its own `testWidgets`, so one failure doesn't
stop the others.

## Adding a scenario

Add an entry to `scenarios` in `shots_test.dart`:

```dart
Scenario('stats', _all, (t, d) async {
  await openApp(t);                                   // the app, Home tab
  await push(t, ScreenNavigationSetup.statsScreen);   // a page on the nested navigator
}),
```

Helpers there: `openApp(tester, tab: RailTab.podcasts)` pumps the whole app
and opens a tab from the rail as a user does (expanding Songs for Playlists,
Albums and Artists on the phone rail; the wide rail keeps its own selection,
so setting the tab index alone would leave Home highlighted),
`push(tester, route, arguments)` opens a page as `Get.toNamed` does, `tapPill(tester, label)` picks a Podcasts/Audiobooks section,
`growToFeed` makes the surface as tall as the Home feed, and `settle` lets
loading and transitions finish. Pages opened with `Get.to` (book pages) can be
pushed the same way the app does. If the screen reads data that isn't seeded
yet, add it in `src/stores.dart` (Hive) or `src/fakes.dart` (controllers,
`ShotMusicServices`).

## Limits

- GetX's `GetPlatform` reads `dart:io`'s `Platform`, which is Linux under
  `flutter test`. Where the app branches on it, the shots show the desktop
  branch: the Home header lacks the Android-only "What's playing?" mic, and the
  player's queue opens as on desktop. (`defaultTargetPlatform`, which most
  layout code reads, is Android.)
- No network: an RSS show's own page (`PodcastEpisodesScreen`) reads its feed
  over HTTP and parses it in an isolate, so the podcast show page is a
  YouTube Music show (the same `PodcastShowView`). The Inbox is the merged
  episodes as the app caches them.
- Each song has its own cover (albums usually share one), so shelves don't
  look repetitive.
- Dates (greeting, "Your week", episode dates) follow the real clock.
