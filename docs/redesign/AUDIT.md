# UI restyle — Phase 0 audit

Baseline for the "X Lights out, Riff green" restyle (`RIFF_UI_RESTYLE.md`).
Taken on `7f8c1ed` (1.7.134, after Home redesign v2 and Spotify shelves).

## SDK

| | |
|---|---|
| Flutter | 3.24.2 stable (CI pins the same) |
| Dart | 3.5.2 |
| `pubspec.yaml` SDK constraint | `>=3.1.5 <4.0.0` |
| `.metadata` revision | `d211f42860350d914a5ad8102f9ec32764dc6d06` |

Consequences: no `skeletonizer` 3.x (needs Dart ≥ 3.7) → in-house skeleton
(§5.13). Theme classes are the 3.24 names: `DialogTheme`, `TabBarTheme`,
`CardTheme` (not the `*ThemeData` variants), `WidgetStateProperty`.

## Theme

- Built in `lib/ui/utils/theme_controller.dart`, `ThemeController._createThemeData`,
  one branch per `ThemeType` (`dynamic`, `system`, `dark`, `light`).
  `GetMaterialApp` reads `ThemeController.themedata` (`lib/main.dart:170`).
- **Pitch Black** = `ThemeType.dark`, `useMaterial3: false`,
  `ColorScheme.fromSwatch`, surfaces from `RiffSurfaces`
  (`#000000`, `#16181C`, `#1E2026`, hairline `#2F3336`, muted `#8B98A5`,
  text `#E7E9EA`).
- Font: Plus Jakarta Sans fetched at runtime through `google_fonts`
  (`_applyBrandFont`), applied to all theme types.
- Hive `AppPrefs` keys: `themeModeType` (index into `ThemeType`, default 2 =
  dark), `riffAccentColor` (ARGB int, default `0xFF1DB954`),
  `themePrimaryColor` (album-art colour for the dynamic theme).
- Accent variants (`ThemeController.riffAccents`): Green `#1DB954` (default),
  Blue `#4A9EFF`, Violet `#9B59F5`, Crimson `#E0405A`, Amber `#FFB300`,
  Cyan `#1D9BF0` — six, not five; all six are kept.
- Text-slot quirks the widgets depend on: `titleSmall` carries the muted
  colour (read by `homeMutedColor` and ~39 call sites); `labelMedium` is
  22/700; `bodyMedium` is muted.
- Other token files: `lib/ui/utils/riff_tokens.dart` (`RiffTokens` radii
  10/14/18, hairline 0.5, durations 180/260 ms), `lib/ui/screens/Home/home_metrics.dart`
  (`RiffSpacing`, `RiffSizes`, `HomeMetrics`, `RiffSectionHeader`),
  `lib/ui/screens/Home/home_layout.dart` (`HomeLayout`, shared header/card
  styles used by most screens).

## Rail

`lib/ui/widgets/side_nav_bar.dart` — `SideNavBar`, custom column (not a
`NavigationRail`) on phones (< 480 dp), `SideBarAnimated` on wider screens.
`kRailWidth = 47`. Items: Home, Songs (+ Playlists / Albums / Artists
accordion), Podcasts, Audiobooks, Settings (icon only). Test:
`test/home/side_rail_test.dart`.

## Hardcoded styling

`grep -rnE "Color\(0x|Colors\.|fontSize:|fontWeight:|EdgeInsets\.fromLTRB" lib/`

| Pattern | Hits |
|---|---|
| `Color(0x` | 81 |
| `Colors.` | 218 |
| `fontSize:` | 212 |
| `fontWeight:` | 191 |
| `EdgeInsets.fromLTRB` | 135 |
| **Total** | **789** in 113 files |

Top files: `theme_controller.dart` 94 (expected — it is the theme),
`podcasts_library.dart` 39, `podcast_show_view.dart` 22,
`spotify_artist_view.dart` 22, `audiobook_widgets.dart` 20,
`player_video_surface.dart` 18, `long_form_player.dart` 18,
`rewind_screen.dart` 17, `player_control.dart` 17,
`podcast_folder_controller.dart` 16 (folder colours — data, not styling),
`home_layout.dart` 15, `podcast_transcript_sheet.dart` 14,
`free_audiobook_screen.dart` 13, `collection_header.dart` 12,
`word_synced_lyrics.dart` 12, `riff_sheet.dart` 11,
`home_station_chips.dart` 11 (station gradients), `audiobooks_screen.dart` 11.

## Screen → file map

| Screen / part | Files |
|---|---|
| App shell, mini-player host | `lib/ui/home.dart` (`SlidingUpPanel`), `lib/ui/navigator.dart` |
| Left rail | `lib/ui/widgets/side_nav_bar.dart` |
| Home | `lib/ui/screens/Home/home_screen.dart` (`_HomeFeed`, `_HomeHeader`, Explore more), sections from `home_feed_builder.dart` (`buildHomeSections`, unchanged by this project) |
| — Jump back in | `home_jump_back_in.dart` |
| — Riff Wave + station chips | `lib/ui/widgets/discovery/riff_wave_hero.dart`, `home_station_chips.dart` |
| — Speed dial (the "grid") | `home_speed_dial.dart` — a 3×3 paged grid; there is no 6-tile grid in this version |
| — Quick picks | `home_hero_carousel.dart` |
| — Personalized / Spotify / editorial shelves | `home_shelves.dart` (`RiffShelf`, `HomeShelfItem`) |
| — Your week | `home_stats_card.dart` |
| — Section header / metrics | `home_metrics.dart` |
| Explore page | `explore_screen.dart` |
| "Similar to you" | not present as a Home section in this version; closest: player "Similar songs" (`lib/ui/widgets/discovery/player_similar_row.dart`, `similar_songs_sheet.dart`) and "Similar to X" YouTube shelves (rendered by `RiffShelf`) |
| Search | `lib/ui/screens/Search/search_screen.dart`, `search_result_screen_v2.dart`, `components/` |
| Library (Songs, Playlists, Albums, Artists) | `lib/ui/screens/Library/library.dart` |
| Artist | `lib/ui/screens/Artists/artist_screen_v2.dart`, `spotify_artist_view.dart` |
| Album / playlist | `lib/ui/screens/Album/album_screen.dart`, `lib/ui/screens/Playlist/playlist_screen.dart`, `lib/ui/widgets/collection_header.dart`, `song_list_tile.dart`, `list_widget.dart` |
| Mini player | `lib/ui/player/components/mini_player.dart` |
| Full player | `lib/ui/player/player.dart`, `components/standard_player.dart`, `gesture_player.dart`, `player_control.dart`, `albumart_lyrics.dart`, `backgroud_image.dart`, `player_canvas_backdrop.dart` |
| Podcast / audiobook player | `components/long_form_player.dart`, `podcast_player_tint.dart` |
| Lyrics | `components/lyrics_widget.dart`, `word_synced_lyrics.dart`, `lyrics_switch.dart` |
| Queue | `lib/ui/widgets/up_next_queue.dart`, `lib/ui/player/long_form_queue.dart` |
| Podcasts | `lib/ui/screens/Podcasts/podcasts_library.dart` (tab), `podcast_inbox_screen.dart`, `podcast_show_view.dart` (show page), `podcasts_screen.dart` (RSS episodes), `podcast_queue_screen.dart`, `podcast_downloads_screen.dart`, `podcast_subs_screen.dart`, `podcast_settings_screen.dart`, `podcast_stats_screen.dart`, `podcast_bookmarks_ui.dart`, `podcast_segment_ui.dart` |
| Skip-ad pill | `components/player_control.dart`, `components/long_form_player.dart` (`'skipAd'`) |
| Audiobooks | `lib/ui/screens/Audiobooks/audiobooks_screen.dart`, `audiobook_widgets.dart`, `free_audiobook_screen.dart`, `audiobook_detail_screen.dart`, `audiobook_catalog_detail_screen.dart` |
| Settings | `lib/ui/screens/Settings/settings_screen.dart`, `components/` |
| Stats / Rewind | `lib/ui/screens/Stats/stats_screen.dart`, `rewind_screen.dart` |
| Plugins / Spotify / Cloud | `lib/ui/screens/Plugins/*`, `lib/ui/screens/Cloud/*` |
| Sheets | `lib/ui/widgets/riff_sheet.dart`, `songinfo_bottom_sheet.dart`, `sleep_timer_bottom_sheet.dart`, `sort_widget.dart` |
| Dialogs | `create_playlist_dialog.dart`, `song_info_dialog.dart`, `backup_dialog.dart`, `restore_dialog.dart`, `export_file_dialog.dart`, `playlist_export_dialog.dart`, `new_version_dialog.dart`, `common_dialog_widget.dart` |
| Snackbars | `lib/ui/widgets/snackbar.dart` (+ `ScaffoldMessenger` calls) |
| Loading placeholders | `lib/ui/widgets/shimmer_widgets/*` (shimmer package), `ImageWidget._shimmer` |

## Baseline screenshots

`docs/redesign/baseline/` — rendered with the screenshot harness (kept
outside the repo; it fakes controllers and renders each screen to PNG) at
411 dp (phone), 360 dp (small phone) and 900 dp (tablet) where the harness
has those scenarios. JPEG, 1× scale, to keep the repo small.

## Phase 2 result (hardcoded styling → theme)

Same grep, after Phase 2:

| Pattern | Before | After (all `lib/`) | After in `lib/ui` outside `lib/ui/theme/` and `theme_controller.dart`, real hits |
|---|---|---|---|
| `Color(0x` | 81 | 92 | 0 |
| `Colors.` | 218 | 173 | 1 |
| `fontSize:` | 212 | 7 | 4 (computed) |
| `fontWeight:` | 191 | 8 | 1 |
| `EdgeInsets.fromLTRB` | 135 | 0 | 0 |

"All `lib/`" still counts the theme itself (`lib/ui/theme/`, the light and
album-colour themes in `theme_controller.dart`), the data palettes moved to
`lib/ui/theme/palettes/`, `lib/services/` (podcast segment category colours —
data), `Colors.transparent` (no colour) and names that merely end in
"Colors" (`RiffColors.of`, `PodcastFolderColors`).

Documented exceptions (allowed by the rules or not styling):

| Where | What | Why |
|---|---|---|
| `widgets/cust_switch.dart` | `primaryColor == Colors.white` | theme detection in logic, not a style |
| `player/components/word_synced_lyrics.dart` (2) | `fontSize: base + 2/3` | karaoke emphasis grows the active line relative to its slot |
| `screens/Podcasts/podcast_playback_controls.dart` | `fontSize: size * 0.27`, `w800` | seconds glyph drawn inside a scaled skip icon |
| `widgets/letter_art.dart` | `fontSize: size * 0.42` | the letter scales with the artwork it sits on |
| everywhere | `Colors.transparent` | "no colour", not a palette value |

Data palettes (content colours, not chrome) now live in
`lib/ui/theme/palettes/`: Home stations, podcast folders and categories,
audiobook genres and rating star.

Fixed-height rows and shelves that computed their height from the old font
metrics now measure the TextTheme slot their text uses
(`lib/ui/theme/riff_text_metrics.dart`), so they can't overflow.

## Phase 3 result (rail + page headers)

- Rail (`side_nav_bar.dart`): width 47, items, order, labels and
  Semantics unchanged (`test/home/side_rail_test.dart` untouched and
  green). Colours, label style and glyph sizes come from the theme's
  `NavigationRailThemeData` and `RiffComponentSizes`.
- Headers: `lib/ui/widgets/riff_header_bar.dart` — `RiffHeaderBar`
  (header chrome + hairline for pinned headers, via the Scaffold's
  `ScrollNotificationObserver`), `RiffAppBar` (same for `AppBar`s) and
  `RiffScrollUnder` (hairline at the top of content below pinned tabs or
  sort rows). Covered by `test/theme/riff_header_bar_test.dart`.
- Screenshots: `docs/redesign/phase3/`.
