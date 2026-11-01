# Riff-mobile — X-Style UI Restyle ("X Lights out, Riff green")

Riff's look is the 2026 X app's "Lights out" theme on Riff's pure-black OLED background, with
the accent the user picks (green by default).

**Status, updated for 1.7.156 (November 2026): done.**

- The restyle shipped as Phases 0–9 in 1.7.135–1.7.142 (PRs #117–#125). It was visual only:
  nothing moved.
- From 1.7.143 to 1.7.153 the owner asked for layout changes that "nothing moves" didn't allow
  (§7.2).
- The v2 redesign (1.7.153–1.7.156, `docs/redesign/V2.md`) brought Home, the library, Podcasts
  and Audiobooks closer to Spotify, YouTube Music, Apple Music, Pocket Casts and Audible (§7.3).

This file used to be the plan, written against 1.7.133 (PR #115). It now describes the design
system as the code has it. Values come from the token files listed in §4. If this file and the
code disagree, the code is right and this file needs fixing.

---

## How to use this file

1. The **Rules** (§3) are in `CLAUDE.md` and apply to every UI change.
2. Use the **token** names in §4 in code. Each table says which file and class a value lives in.
3. The **component specs** in §5 say how each kind of component looks. An *As built* note marks
   each place the app differs from the original spec, and says why.
4. **Layout changes** happen only when the owner asks for them. Log each one in
   `docs/redesign/SKIPPED.md` as `N (revised after 1.7.x) | spec item | The owner asked … | what
   was done`. Redesign work also goes under its area in `docs/redesign/V2.md`.
5. **Check** each change with the screenshot harness (§8) on phone, small phone and tablet before
   pushing.

---

## 1. Scope

### What a restyle may change
- Colors, typography (font family, sizes, weights, line heights), letter spacing
- Padding, gaps, margins, section spacing, row heights, artwork sizes, corner radii
- Dividers/hairlines, borders, removal of shadows/elevation, card backgrounds
- Icon style (outline vs. filled), icon sizes, icon colors
- Styling of buttons, pills, chips, switches, sliders, progress bars, text fields, tabs
- Styling of bottom sheets, dialogs, menus, snackbars, loading states (spinners/skeletons)
- Press/hover/selected states, animation durations and curves, haptic feedback on existing actions

### What stays unless the owner asks
- **Element positions.** Nothing is moved, added, removed or reordered on its own initiative.
  Owner-requested changes are logged (§7.2, §7.3).
- **The left side rail.** It keeps its width (`kRailWidth` = 47, `lib/ui/widgets/side_nav_bar.dart`),
  its place and its behavior. There is no bottom tab bar and no drawer. The current items, in
  order: Home, Discover, Songs (its Playlists / Albums / Artists accordion opens under it),
  Podcasts, Audiobooks, Settings. The indices are in `RailTab`
  (`lib/ui/screens/Home/home_screen_controller.dart`). The owner added Discover in 1.7.147.
- **The Home section set and order.** `buildHomeSections` (`lib/ui/screens/Home/home_feed_builder.dart`)
  and its tests don't change. Today's `HomeSection` order is header, jumpBackIn, speedDial,
  quickPicks, personalized, spotify, yourWeek, editorial, exploreMore. The owner moved Riff Wave
  and its station chips to Discover in 1.7.149, and the genre and mood chips live on Discover too.
  New shelves inside a section (Recently played, New episodes, Your shows, Your audiobooks under
  Made for you) are logged as owner requests.
- **Component arrangement**: a carousel stays a carousel, a grid stays a grid, a card keeps its
  internal element order.
- **The mini player, `SlidingUpPanel`, routing (`Get.to`) and screen structure.** No
  hide-on-scroll chrome, no new settings.
- **All logic**: playback, queue, downloads, RSS and YouTube podcasts, chapter ad-skip,
  SponsorBlock, sync, Android Auto, Hive `AppPrefs` persistence.

If a spec line would move, add or remove an element and the owner hasn't asked for it, skip it and
log it in `docs/redesign/SKIPPED.md` with the reason. Don't improvise layout changes.

---

## 2. Design language: "X Lights out, Riff green"

1. Content sits directly on `#000000`. Structure comes from spacing first, and from
   1-physical-pixel hairlines (`#2F3336`) where a list or group needs one. No elevation, and no
   shadows except scrims under text on artwork.
2. Grey `surface1` boxes are used only where a surface is the component itself: sheets, dialogs,
   menus, the floating mini player, Home tiles (Jump back in, Speed dial, Quick picks), the Riff
   Wave card and skeletons.
3. There are three text levels: primary `#E7E9EA`, secondary `#71767B`, and the accent (for
   interactive or "on" things only).
4. Icons are outline when inactive and filled when active.
5. **The accent is used only for:** the active navigation item; play buttons; progress; toggled-on
   states; primary buttons; links and text buttons (including a shelf's "See all" chevron);
   selected chips; the now-playing mark (the title and the equalizer bars on the playing row);
   the Skip-ad pill; snackbars; spinners. Nothing decorative.
6. Typography is dense and bold: 15 px body, 800-weight headers, tight line heights. Rail tabs
   open on a large page title (24/800).
7. Press feedback is a flat highlight (`#202327`), with no ink ripple anywhere
   (`NoSplash.splashFactory`). Cards and tiles also shrink a touch under the finger
   (`RiffPressScale`, 0.96).

---

## 3. Rules (in CLAUDE.md)

This block matches `CLAUDE.md`. Change both together.

```markdown
## UI restyle: "X Lights out, Riff green" (active project, see RIFF_UI_RESTYLE.md)

1. Visual only. Never move, add, remove, or reorder UI elements. The left rail stays (same width,
   items, order). Home section set/order stays (buildHomeSections + its tests unchanged).
   If a spec item needs a layout change, skip it and log it in docs/redesign/SKIPPED.md.
2. ThemeData is the single source of truth. Colors via Theme.of(context).colorScheme or the
   RiffColors ThemeExtension; text via Theme.of(context).textTheme; component styling via
   component themes in ThemeData. No Color(0x...), Colors.*, inline TextStyle(fontSize/fontWeight),
   or magic numbers in widget code. copyWith at call sites may only change color.
3. Spacing only from RiffSpacing (extend the existing class, don't create a parallel one).
   Use EdgeInsets.only / EdgeInsets.symmetric, never EdgeInsets.fromLTRB.
4. Background is always #000000. Album-art dynamic color may only tint the full-player gradient (≤20% opacity).
5. Accent (user-selected: green default; Blue/Violet/Crimson/Amber must keep working) is used only
   for the elements listed in RIFF_UI_RESTYLE.md §2.5.
6. Behavior must not change: playback, queue, downloads, podcasts, chapter ad-skip, SponsorBlock,
   sync, Android Auto, settings persistence.
7. GetX hygiene: every Obx reads at least one observable; controllers clean up in onClose().
8. Don't upgrade Flutter/Dart for this project. Use APIs available in the project's current SDK.
9. Each phase: one branch/PR, small commits, `flutter analyze` clean,
   `flutter test --exclude-tags live` green, screenshot harness run on phone / small phone / tablet,
   before/after screenshots in the PR body.
```

How the rules apply now:
- **Rule 1.** Layout changes the owner asks for are allowed. Log them as in "How to use this
  file". The rail's width and the Home section enum still don't change without such a request.
- **Rule 4.** The owner made one exception in 1.7.153: in the dark themes, the music player's page
  takes the cover's own colour, held dark enough for white text at 6:1 or better
  (`SKIPPED.md`, "6 (revised after 1.7.152)"). The light theme, video and the
  podcast/audiobook player keep the ≤ 20% tint (`RiffPalette.playerTintOpacity`).
- **Rule 5.** There are six accents, not five: Cyan too (§4.1).
- **Rule 8.** The SDK is Flutter 3.24.2 / Dart 3.5.2 (CI pins the same).

---

## 4. Design tokens

### Where things are

| What | Where |
|---|---|
| Colours, opacities, radii, motion, component sizes, generated-cover art, `RiffColors` | `lib/ui/theme/riff_tokens.dart`: `RiffPalette`, `RiffRadii`, `RiffDurations`, `RiffMotionDistances`, `RiffFastScroll`, `RiffComponentSizes`, `RiffCoverArt`, `RiffColors` |
| Spacing and Home sizes | `lib/ui/theme/riff_spacing.dart`: `RiffSpacing`, `RiffSizes` |
| The theme | `lib/ui/theme/riff_theme.dart`: `RiffTheme.dark(accent)`, `RiffTextStyles`, `riffExpansionTileTheme()`, `riffActionIconTheme()` |
| Text scale | `lib/ui/theme/riff_text_metrics.dart`: `kRiffMaxTextScale` (1.3), `riffTextScaler`, `riffLineHeight`, `riffLineBox` |
| Data palettes (generated covers, station gradients, podcast folder colours, genre colours, rating) | `lib/ui/theme/palettes/` |
| Theme type, accents, the light and album-colour themes | `lib/ui/utils/theme_controller.dart` (`riffAccents`). Pitch Black (`ThemeType.dark`) builds `RiffTheme.dark` |
| Motion kit | `lib/ui/widgets/riff_motion.dart`: `RiffFadeIn`, `RiffSwitcher`, `RiffPressScale` |
| Page headers | `lib/ui/widgets/riff_header_bar.dart`: `RiffPageTitle`, `RiffHeaderBar`, `RiffAppBar`, `RiffScrollUnder`; `lib/ui/screens/Home/home_layout.dart`: `RiffPageHeader`, `HomeSectionHeader` |
| Sheets | `lib/ui/widgets/riff_sheet.dart` |
| Skeletons | `lib/ui/widgets/shimmer_widgets/basic_container.dart`: `RiffSkeletonPulse`, `BasicShimmerContainer` |
| Other shared widgets | `riff_equalizer.dart`, `riff_fast_scroller.dart`, `riff_marquee.dart` in `lib/ui/widgets/` |

The old `lib/ui/utils/riff_tokens.dart` (`RiffTokens`), and `RiffSpacing` in `home_metrics.dart`,
are gone. Phase 1 folded them into the files above.

### 4.1 Colours (`RiffPalette`, `RiffColors`)

| Token | Value | Maps to | Use |
|---|---|---|---|
| `bg` | `#000000` | `colorScheme.surface`, `scaffoldBackgroundColor` | All backgrounds, rail, headers, player |
| `surface1` | `#16181C` | `colorScheme.surfaceContainerLow` | Sheets, dialogs, menus, skeleton boxes, Riff Wave card, Home tiles, mini player |
| `surface2` | `#202327` | `colorScheme.surfaceContainerHigh`, `RiffColors.surface2`, `highlightColor` | Pressed highlight, switch off-track |
| `divider` | `#2F3336` | `colorScheme.outlineVariant`, `dividerColor` | Hairlines, card and chip borders, inactive slider track |
| `outlineStrong` | `#536471` | `colorScheme.outline` | Outline-button border, switch off-outline |
| `textPrimary` | `#E7E9EA` | `colorScheme.onSurface` | Titles, body, active icons (non-nav) |
| `textSecondary` | `#71767B` | `colorScheme.onSurfaceVariant` | Metadata, inactive icons, timestamps, inactive tab labels |
| accent | the user's (below) | `colorScheme.primary` and `secondary` | §2.5 only |
| `onAccent` | `#000000` | `colorScheme.onPrimary` | Text and icons on accent fills |
| `accentMuted` | accent at 12% over black | `RiffColors.accentMuted` | Selected chip fill, now-playing row tint |
| `handle` | `#333639` | `RiffColors.handle` | Sheet drag handle |
| `barrier` | `#5B7083` at 40% | `RiffColors.barrier` | Modal barrier behind sheets and dialogs |
| `danger` | `#F4212E` | `colorScheme.error` | Destructive actions, errors |
| `onImage` | `#FFFFFF` | `RiffColors.onImage` | Text and icons over artwork or a scrim, in every theme |
| `scrim` | `#000000` | `RiffColors.scrim` | Darkening layers over artwork (always used with an opacity) |

**Accents** (`ThemeController.riffAccents`, stored as `riffAccentColor` in `AppPrefs`):

| Name | Hex |
|---|---|
| Green (default) | `#1DB954` |
| Blue | `#4A9EFF` |
| Violet | `#9B59F5` |
| Crimson | `#E0405A` |
| Amber | `#FFB300` |
| Cyan | `#1D9BF0` |

The accent sets `primary`, `secondary` and `accentMuted`; nothing else derives from it.

**Opacities** are also named in `RiffPalette`, so no widget writes a bare `withOpacity(0.x)`.
Examples: `trackOpacity` 0.12 (unfilled progress), `lyricsDimOpacity` 0.6,
`unavailableOpacity` 0.38, `playerTintOpacity` 0.2, `playerSecondaryText` 0.7,
`tileTitleScrim` 0.72, `coverBadgeScrim` 0.65, `railActiveFillOpacity` 0.16 /
`railActiveBorderOpacity` 0.28.

Other colour rules:
- `surfaceTint` is transparent (set in the theme only), so Material 3 elevation never greys a surface.
- Contrast: `#E7E9EA` on black is about 17.2:1; `#71767B` on black about 4.58:1, which just passes
  WCAG AA. Never put `textSecondary` body text on `surface1` or lighter.
- The light and album-colour themes keep their own palettes and share the Inter type scale.
  `RiffColors.of` and `RiffTextStyles.of` give them fallbacks.

### 4.2 Spacing (`RiffSpacing`, `lib/ui/theme/riff_spacing.dart`)

```dart
class RiffSpacing {
  static const double unit = 4;
  static const double xxs = 2;
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 20;
  static const double xxl = 24;
  static const double x3l = 32;

  static const double gutter = 16;          // content margin from the rail and the right edge
  static const double section = lg;         // space above every section (16)
  static const double headerRow = 48;       // a section's title row
  static const double headerToContent = xs; // title row → content (4)
  static const double cardGap = 12;         // between cards on a shelf
  static const double gridGap = 8;          // inside grids (Jump back in, Speed dial)
  static const double chipRowTop = 12;      // Riff Wave card → its station chips (Discover)
  static const double listEnd = 200;        // room under lists for the mini player
  static const double snackbarBottom = 100; // snackbars float above the mini player
}
```

| Usage | Value |
|---|---|
| Screen gutter | 16 |
| List row padding | 16 horizontal, 12 vertical (rows with a fixed extent keep it) |
| Artwork → text gap | 12 |
| Title → subtitle gap | 2 |
| Section rhythm (Home and app-wide section titles) | 16 above the 48 dp title row, 4 below it: about 28 dp from the content above to the title, and 16 from the title to the covers |
| Chip gap | 8 |

*As built:* the restyle spec had a 32 dp Home section gap with a hairline between sections. v2
dropped the hairlines and moved to the 16 + 48 + 4 rhythm (Spotify, YouTube Music, Apple Music).
See `V2.md`, "Home (first pass)".

### 4.3 Radii (`RiffRadii`, Home ones in `RiffSizes`)

| Token | Value | Use |
|---|---|---|
| `xs` | 4 | Song-row thumbnails, song art in a shelf header |
| `sm` | 8 | Album/playlist art, grid tiles, landscape/desktop player art, snackbars (`RiffSizes.tileRadius` / `shelfRadius` / `carouselRadius` are 8 too) |
| `lg` | 16 | Riff Wave card (`RiffSizes.waveRadius`), sheet top corners, dialogs |
| `pill` | 999 | Buttons, chips, search field, Skip-ad pill |
| `miniPlayer` | 24 | The floating mini-player card |

### 4.4 Sizes (`RiffComponentSizes`; Home ones in `RiffSizes`)

| Element | Value |
|---|---|
| Song/episode row artwork | 48 (`rowArt`) |
| Song row extent / wide album-playlist row / artist row | 75 / 96 (art 76) / 72 (kept from before the restyle) |
| Mini-player artwork | 40 (`miniArt`) |
| Header icon | 22 |
| Row trailing icon (⋮, download…) | 20, `textSecondary`; compact hit box 32 (`rowIconHit`) |
| Rail glyph | 22 in an 8 dp-padded box, 18 in 6 for the Songs children (the pre-restyle look, §5.14) |
| Icon-button hit area | 40 (48 where it was already 48; touch targets never shrink) |
| Buttons | 36 compact, 40 default |
| Chip | 32 (inside the existing 48 dp touch rows) |
| Search field | 40 |
| Full-player seek bar | track 2, thumb 12 while dragging |
| Sheet handle | 36 × 4 |
| Sheet row | min 52, icon 22 |
| Settings row | min 52 |
| Skip-ad pill | 36 tall, icon 16, slides 8 |
| Spinner | 24, stroke 2.5 |
| Shelf header picture | 40 (`shelfHeaderArt`) |
| "See all" grid card | about 168 wide (two columns on a phone), wide cards 300 |
| Speed dial tile | grows to 200 on a tablet (`RiffSizes.speedTileMax`); about 105 on a phone |
| Up Next tab (music player) | 30 above the system inset, arched top dropping 12 (`queueCard`, `queueCardArc`) |

`RiffComponentSizes` holds the full list, one documented constant per size. Add new sizes there,
not in widgets.

### 4.5 Typography: Inter, bundled (no runtime font fetching)

X uses Chirp, which is proprietary. Inter (SIL OFL, `assets/fonts/Inter-LICENSE.txt`) is the
closest free match. Weights 400, 500, 600, 700 and 800 are in `assets/fonts/`, registered in
`pubspec.yaml` as family `Inter`. Letter spacing is 0 everywhere except on generated-cover titles.

| TextTheme slot | Size / line height | Weight | Default colour | Used for |
|---|---|---|---|---|
| `displayLarge` / `displayMedium` / `displaySmall` | 40/44 · 34/40 · 28/32 | 800 | primary | Big numbers: the sleep-timer countdown, Rewind and podcast stats totals |
| `headlineLarge` / `headlineMedium` | 28/32 · 26/30 | 800 | primary | Rewind headings, the sleep timer's custom length |
| `headlineSmall` | 24 / 28 | 800 | primary | Page titles on rail tabs, the Home greeting, album/artist/show titles |
| `titleLarge` | 20 / 24 | 800 | primary | Pushed-page header titles, sheet and dialog titles, section titles |
| `titleMedium` | 15 / 20 | 700 | primary | Row titles, names |
| `titleSmall` | 14 / 18 | 500 | secondary | Muted small labels; Home shelf card titles in the text colour (v2: 14 medium) |
| `bodyLarge` | 15 / 20 | 400 | primary | Body, descriptions, settings titles, dialog body |
| `bodyMedium` | 13 / 16 | 400 | secondary | Metadata, subtitles, timestamps |
| `bodySmall` | 12 / 16 | 400 | secondary | Small captions |
| `labelLarge` | 15 / 20 | 700 | primary | Buttons, active tab labels |
| `labelMedium` | 14 / 18 | 600 | primary | Chips |
| `labelSmall` | 12 / 16 | 600 | secondary | Captions, times, pills, tooltips |

Styles with no TextTheme slot are in the `RiffTextStyles` ThemeExtension:

| Style | Size / line height | Weight | Use |
|---|---|---|---|
| `cardTitle` | 17 / 22 | 800 | Riff Wave card title |
| `tileTitle` | 13 / 16 | 700 | Speed dial tile title |
| `playerTitle` | 22 / 28 | 800 | Full-player track title |
| `pillLabel` | 13 / 16 | 700 | Skip-ad pill |
| `coverTitle` / `coverTitleCompact` | 22/23, −0.7 · 17/18, −0.5 | 800 | Title on a generated playlist cover (white, scales with the cover) |

Text follows Android's font size from 1.0× up to 1.3× (`kRiffMaxTextScale`). Rows with a fixed
height size themselves with `riffLineHeight` / `riffLineBox`, so large text never clips. Three
font sizes in widgets are computed and documented as exceptions: karaoke emphasis in
`word_synced_lyrics.dart`, the seconds glyph in `podcast_playback_controls.dart`, and
`letter_art.dart`.

### 4.6 Icons
- An outline glyph means inactive or off; a filled glyph means active or on (e.g.
  `Icons.favorite_border` → `Icons.favorite`).
- Icons default to `textPrimary`. Metadata and trailing icons use `textSecondary`; toggled-on
  icons use the accent.
- Back buttons are the rounded chevron (`Icons.arrow_back_ios_new_rounded`) in every theme
  (`riffActionIconTheme`).

### 4.7 Motion and haptics (`RiffDurations`, `RiffMotionDistances`, `riff_motion.dart`)

| Item | Value |
|---|---|
| Press highlight | 100 ms (`press`), `surface2`, no splash |
| Press scale on cards and tiles | 0.96 (`pressScale`), springs back on release |
| Selected state / tab indicator / settings group expand | 200 ms (`select`), `Curves.easeOutCubic` |
| Sheet open | 250 ms (`sheet`) |
| Content replacing its skeleton | 250 ms fade (`content`) + 8 dp rise (`contentRise`), `RiffFadeIn` |
| One section's content giving way to another (chips, pills, modes) | 250 ms, `RiffSwitcher` |
| Rail tabs and search filters | shared-axis fade-through, 30 dp slide (`sharedAxis`) |
| Cover loading | 200 ms fade (`image`) |
| Track change (cover, title, artist) | 300 ms crossfade (`trackChange`) |
| Colour following the cover | 600 ms (`colour`) |
| Cover flight from a card to its page | `Hero` (albums, playlists, shows, books); player minimise/expand morphs the cover (`HeroArtMorph`) |
| Skip-ad pill appear | 200 ms fade + 8 dp slide up |
| Skeleton pulse | opacity 0.5 ↔ 1.0, 1200 ms (`skeletonPulse`) |
| Curves | enter `easeOutCubic`, exit `easeInCubic`, a toggle turning on `easeOutBack` |

Every animation honours Android's **Remove animations**: skeletons hold still, the equalizer and
canvas stop, and titles don't scroll.

Haptics fire on *existing* actions only:
- `HapticFeedback.selectionClick()`: rail item tap, tab change, chip select
- `HapticFeedback.lightImpact()`: like, add to playlist/queue, play next, download start
- `HapticFeedback.mediumImpact()`: long-press menu open, pull-to-refresh trigger
- Never `heavyImpact`.

*As built:* page transitions keep their types (Zoom on Android) and their own durations. Flutter
3.24's `PageTransitionsTheme` builders fix their durations, so the 250 ms target was skipped
(`SKIPPED.md`, Phases 1 and 8).

---

## 5. Component specs

### 5.1 Hairlines
`DividerThemeData(color: divider, thickness: 0)`. Thickness 0 renders exactly one physical pixel.
Borders are `BorderSide(color: divider, width: 0)`. Tab strips use 0.5 (`tabDivider`), because a
TabBar divider can't be 0.

*As built:* `space` stays at Material's 16, because 12 `Divider()` call sites depend on it.

### 5.2 List rows (songs, search results, library items)
- Padding 16h / 12v, artwork 48 at radius 4, gap 12.
- Title `titleMedium`, one line with ellipsis. Subtitle `bodyMedium`, one line: the artist, with
  the "E" badge for explicit songs and the download mark for downloaded ones.
- Trailing ⋮ is 20 `textSecondary`.
- Press: a `surface2` highlight, no ripple.
- Now playing: the title in the accent, the animated equalizer bars, and an `accentMuted` tint.
- Separators: an inset hairline (from the text, 76 from the left) in album, playlist and library
  track lists; a full-width hairline in search results, episode lists and settings.
- A song that won't play (explicit while explicit content is off, or needing a connection while
  there's none) dims to 38% (`UnplayableDim`).
- Swipe and long-press actions are also TalkBack custom actions.

*As built:* rows with a fixed extent (75 song rows, 96 wide rows, 72 artist rows, 64 queue rows)
keep it. The padding fits inside.

### 5.3 Cards on shelves (albums, playlists, artists, shows, books)
- No card background, border or elevation.
- Artwork radius 8. Artists stay circular.
- Title: `titleSmall` in the text colour (14 medium) on Home shelves and their See all pages (v2).
  One line. Subtitle `bodyMedium`, one line. 8 dp from the art to the title.
- Shrinks to 0.96 under the finger.
- One look per kind of thing (`V2.md`, Principles): a playlist card on Home, in the library grid
  and on an artist page is the same card.

### 5.4 Section headers
- Title `titleLarge` in sentence case, gutter 16, on the 16 + 48 + 4 rhythm (§4.2). No hairline
  between Home sections.
- On Home, a header can have:
  - a muted line over the title ("Similar to", "Because you liked", "Spotify" over the first
    Spotify shelf);
  - a 40 dp picture before it (round for an artist or account, a cover with 4 dp corners for a
    song). The name and picture open that page.
- A long card shelf has a "See all" chevron in the accent. It opens `HomeShelfScreen`, with every
  card in a grid. Song-row shelves have Play all instead.
- Pushed pages and sections elsewhere use the same bold sentence-case style.

*As built:* "See all" stays the existing chevron, not a 15/700 text button.

### 5.5 Buttons

| Type | Style |
|---|---|
| Primary (`FilledButton`) | Pill, accent fill, `onAccent` 15/700, height 36/40, padding 16h, no elevation |
| Secondary (`OutlinedButton`) | Pill, transparent, 1px `outlineStrong` border, `textPrimary` 15/700 |
| Text (`TextButton`) | `accent` 15/700, no background |
| Icon (`IconButton`) | 40 hit area, icon 20–22, circular `surface2` highlight on press |
| Round Play on album/playlist/artist headers | accent circle 52, glyph 32 (kept size) |

### 5.6 Chips (station chips, genre chips, filters, section pills)
- Height 32, pill radius, padding 12h, `labelMedium` (14/600).
- Unselected: transparent fill, 1px `divider` border, `textPrimary` label.
- Selected: `accentMuted` fill, 1px accent border, accent label.
- No checkmark unless one existed already.

*As built:* a station chip shows the selected look while its station is starting. The Podcasts
Inbox chip opens its filter menu when tapped again ("Inbox ▾").

### 5.7 Tabs (existing tab strips only)
- Label 15/700 `textPrimary` when active, 15/500 `textSecondary` when inactive.
- Indicator: 4 px tall, fully rounded, accent, as wide as the label.
- A hairline under the strip; no tab background colour; no splash.

### 5.8 Inputs
- Search field: `surface1` fill, pill radius, height 40, no border. Focused: a 1px accent border.
  Placeholder 15/400 `textSecondary`; leading search icon 20 `textSecondary`; a clear button in
  the trailing slot while there is text. Discover's search pill opens the Search screen.
- Other text fields: transparent, 1px `divider` border at radius 4; focused 2px accent; label
  `textSecondary`.

### 5.9 Switches, sliders, progress
- Switch on: track accent, thumb `onAccent`. Off: track `surface2`, outline `outlineStrong`,
  thumb `textSecondary`.
- Slider: active accent, inactive `divider`, thumb accent 12.
- Linear progress: 2–3 px, accent on the text colour at 12%. Episode and book progress lines are 2.
- Circular spinner: accent, stroke 2.5, size 24.
- `RefreshIndicator`: accent on `surface1`.

### 5.10 Bottom sheets and menus (`riff_sheet.dart`)
- Background `surface1`, top radius 16, barrier `#5B7083` at 40%. On tablets a sheet is at most
  500 wide (`sheetMaxWidth`).
- Handle 36 × 4 in `handle`, 8 from the top. Only sheets that already had a handle or title got one.
- Rows: min height 52, padding 16h, icon 22 `textPrimary`, label 15/400 `textPrimary`.
  Destructive rows use `danger`; section separators are hairlines.
- Sheet title, if any: `titleLarge`.
- The players' tools are rows at the top of their ⋮ sheets (§5.17).

### 5.11 Dialogs
- Background `surface1`, radius 16, barrier `#5B7083` at 40%.
- Title `titleLarge`; body `bodyLarge` in `textPrimary`. Secondary grey on `surface1` fails the
  contrast rule in §4.1.
- Actions are pill buttons (§5.5) in their existing order.

### 5.12 Snackbars
Floating, margin 16 (bottom 100, above the mini player), radius 8, accent fill, text 15/600
`onAccent`. The action uses `onAccent` from the theme (*as built*: not 15/800).

### 5.13 Loading skeletons
Flutter 3.24 ships Dart 3.5, and `skeletonizer` 3.x needs 3.7, so skeletons are in-house:
`BasicShimmerContainer` draws `surface1` boxes at the real widgets' radii, and
`RiffSkeletonPulse` pulses their opacity 0.5 ↔ 1.0 over 1200 ms. They hold still under Remove
animations. Loaded content fades in where its skeleton was (`RiffFadeIn`). Screens that showed
spinners keep them, restyled per §5.9.

### 5.14 Side rail (`side_nav_bar.dart`)
- Width 47, black, on phones (< 480 dp). Wider screens use the `sidebar_with_animation` bar
  (black, flat `surface2` press colours, Inter labels, accent indicator).
- Items top to bottom: Home, Discover, Songs (Playlists / Albums / Artists open under it),
  Podcasts, Audiobooks, Settings.
- Active item: an accent box behind the glyph (16% fill, 28% outline at 0.5, radius 12). Inactive
  items are muted. Glyph 22 (18 for the Songs children). Rotated labels in
  `titleMedium`/`bodyLarge`, 6 dp from the glyph.
- A selection click on tap. Tooltips and Semantics labels are kept.

*As built:* Phase 3 made the rail lights out (no indicator, 24 dp outline/filled glyphs, 11/600
labels, a right hairline). The owner preferred the previous look, which came back in 1.7.143.

### 5.15 Page headers
- Rail tabs (Home, Discover, Library, Podcasts, Audiobooks, Settings) start just under the status
  bar with a large page title (`headlineSmall`, 48 dp row). Home has the greeting.
- Pushed pages: black, title `titleLarge`, icons 22 outline `textPrimary`.
- A bottom hairline fades in (200 ms) only while content scrolls under the header
  (`RiffScrollUnder`). Where tabs or a sort row sit under the header, the hairline runs along the
  top edge of the scrolling content.

### 5.16 Mini player
- A floating `surface1` card with a hairline edge and radius 24. It keeps its place and height.
- Artwork 40, round. Title 15/700; artist 13 `textSecondary`.
- Play/pause 28 and next 24, both `textPrimary`. A 2 dp accent progress line along its bottom edge.
- The whole pill follows the finger, with the next or previous track peeking in.
- On tablets the right-hand buttons show as many as fit, most important first.

### 5.17 Full player
- **Music player, dark themes:** the full-bleed cover over a page in the cover's own colour, held
  dark enough for ≥ 6:1 white text and darkening to the bottom. A second cover colour glows
  behind the transport (owner request, §3 rule 4).
- **Light theme, video, and the podcast/audiobook player:** black with at most a 20% cover tint
  at the top.
- Title `playerTitle` (22/800). The artist line uses the text colour at 70% so it stays readable
  over the cover colour. A song with several artists opens "Choose artist".
- Seek bar: a 2 dp track, accent active part, 12 dp thumb only while dragging, times in
  `labelSmall`. Tap the end time to show the time left.
- Play/pause is an accent circle with an `onAccent` glyph. Prev/next are rounded glyphs in the
  text colour. Shuffle and repeat use the accent when on.
- The music player's tools (lyrics, sleep timer, radio, add to playlist, share) are in its ⋮
  sheet; the podcast/audiobook player's are at the top of its top-bar ⋮.
- The line being sung shows under the title for songs with synced lyrics; a tap opens the full
  lyrics.
- Lyrics: the current line in `textPrimary`, other lines at 60%. Word-synced lyrics grow the
  sung word.
- Up Next is an edge-to-edge 30 dp tab with an arched top ("Up Next · next song"). The queue
  panel has Up Next / Similar songs chips.

### 5.18 Podcasts, audiobooks, Skip-ad pill
- Episode rows: artwork 48 at radius 8; title `titleMedium`, at most 2 lines; a meta line
  (show · date · length) in `bodyMedium`; Trailer / Bonus / season labels; a 2 dp accent progress
  line; full-width hairlines.
- Show and book pages: artwork radius 8 with no wash behind it; title `headlineSmall`; author
  `bodyMedium`. Subscribe is a primary pill and Subscribed an outline pill.
- The cover flies from its card to the page.
- **Skip-ad pill:** 36 tall, pill radius, accent fill, `onAccent` `pillLabel` + 16 dp skip glyph.
  It appears with a 200 ms fade and an 8 dp slide up, in the same position as before.

### 5.19 Settings, Stats, Rewind
- Settings rows: min 52, title `bodyLarge`, subtitle `bodyMedium`, switches per §5.9. Group
  headers are bold at list size, with a hairline along each group's bottom edge.
- Stats and Rewind: outlined tiles, the accent for the primary series, `textSecondary` for axes
  and labels, `divider` for gridlines. Top songs show their covers.

---

## 6. Phases (done)

Each phase was one PR, `flutter analyze` clean and `flutter test --exclude-tags live` green, with
harness screenshots on phone, small phone and tablet in `docs/redesign/<phase>/`.

| Phase | What | Release | PR |
|---|---|---|---|
| 0 | Audit and baseline: SDK, theme, rail, hardcoded-styling counts, screen → file map (`AUDIT.md`, `baseline/`) | 1.7.135 | #117 |
| 1 | Tokens, `RiffColors`, `RiffTheme.dark(accent)`, bundled Inter, all six accents | 1.7.135 | #117 |
| 2 | Hardcoded colours, text styles, padding and `fromLTRB` moved onto the theme and tokens | 1.7.136 | #118 |
| 3 | Rail and page headers (scroll-under hairline) | 1.7.137 | #119 |
| 4 | Home restyled in place | 1.7.138 | #120 |
| 5 | Lists: Search, Library, artist, album, playlist, queue; tabs; skeletons | 1.7.139 | #121 |
| 6 | Mini player and full player | 1.7.140 | #122 |
| 7 | Podcasts, Audiobooks, Skip-ad pill (with its widget test) | 1.7.141 | #123 |
| 8 | Sheets, dialogs, menus, snackbars, Settings, Stats, motion, haptics | 1.7.142 | #124 |
| 9 | QA: renders in `after/`, same-place check, styling counts (`QA.md`) | — | #125 |

Every skipped or adjusted spec line, with the reason, is in `docs/redesign/SKIPPED.md`.

### Hardcoded styling, then and now

`grep -rnE "Color\(0x|Colors\.|fontSize:|fontWeight:|EdgeInsets\.fromLTRB" lib/`

| Pattern | Phase 0 (`lib/`) | 1.7.156 (`lib/`) | 1.7.156, real hits in widget code |
|---|---|---|---|
| `Color(0x` | 81 | 160 | 0 |
| `Colors.` | 218 | 178 | 0 |
| `fontSize:` | 212 | 4 | 3 (computed, §4.5) |
| `fontWeight:` | 191 | 4 | 1 (computed) |
| `EdgeInsets.fromLTRB` | 135 | 0 | 0 |

"Widget code" means `lib/ui` outside `lib/ui/theme/` and `theme_controller.dart`. The
`Color(0x` hits are all in the theme and the data palettes in `lib/ui/theme/palettes/`. The
`Colors.` hits are names that end in "Colors" (`RiffColors`, `PodcastFolderColors`),
`Colors.transparent`, and the light and album-colour themes. Keep the widget-code column at zero.

---

## 7. After the restyle

### 7.1 What stayed from the restyle
The Lights-out palette, Inter, the type scale, tokens, component themes, hairlines, the flat
press highlight, the accent rules and the skeletons are unchanged since 1.7.142. Later work
builds on them.

### 7.2 Owner-requested changes (1.7.143–1.7.153)
The layout changes among them are logged in `SKIPPED.md` as "N (revised after 1.7.x)".

| Release | Change |
|---|---|
| 1.7.143 (#126) | The pre-restyle side rail look came back (§5.14) |
| 1.7.144 (#127) | "What's playing?" song recognition, opened from the Home header |
| 1.7.145 (#128) | Up Next became a smaller, rounded card in the player |
| 1.7.146 (#129) | The music player's action row moved into its ⋮ sheet |
| 1.7.147 (#130) | Discover tab on the rail under Home (search pill + Explore feed). Explore and Search left the Home header. Similar songs moved into the swipe-up panel (Up Next / Similar songs chips); Up Next became a 36 dp tab |
| 1.7.148 (#131) | Every player's buttons under ⋮ (the podcast/audiobook tool row and the gesture player's row too), a readable "Playing from", a slimmer 30 dp Up Next tab |
| 1.7.149 (#132) | Riff Wave and its station chips moved from Home to the top of Discover. Generated playlist covers, "Choose artist" for songs with several artists, podcast folder photos, a one-row Inbox (filters in the Inbox chip) |
| 1.7.151 (#134) | Up Next tab edge to edge with a gentle arc |
| 1.7.153 (#135) | Music player coloured by the cover (dark themes), the sung line under the title, cover morph on minimise/expand |

### 7.3 Redesign v2 (1.7.153–1.7.156)
The goal: as good as the best music and podcast apps, layouts included. The rail, theme rules and
behaviour stay. Each area's changes, sources and reasons are in `docs/redesign/V2.md`. In short:

- **Home:**
  - Speed dial tiles carry their title.
  - Song shelves are paged columns of rows, with Play all.
  - No hairlines between sections; the 16 + 48 + 4 rhythm.
  - Shelf headers that say why, and "See all" pages.
  - New shelves: New episodes, Your shows (with new-episode counts), Recently played,
    Your audiobooks.
  - YouTube Music's podcast shelves; Speed dial fills a tablet.
- **Library:** tabs start under the status bar with a large title. Songs has labelled filter
  chips. Riff's own lists get generated covers. Artists are three columns of circles. Long
  lists have a fast-scroll thumb with a letter bubble.
- **Podcasts and Audiobooks:** new episode rows, the Subscriptions grid, the Audiobooks hero card
  and genre chips, one book page for Audiobookshelf and free books, covers flying to their pages.
- **Elsewhere:** Search gets a top result card. Album and playlist pages have a tablet backdrop.
  The artist page gets an About card. Stats has fitting tiles, a weekday chart and covers.
- **App-wide:** bold sentence-case section titles, large page titles on every tab, press scale on
  every card, and a motion pass (fades, shared axis, Hero covers).
- **Accessibility:** TalkBack labels on every control, mini player tap targets, large text up to
  1.3× without clipping.

---

## 8. Checking a change

1. `flutter analyze` is clean.
2. `flutter test --exclude-tags live` is green.
3. The screenshot harness renders the real screens with sample data on a phone (411 dp), a small
   phone (360 dp), a tablet (900 dp) and the small phone at 1.3× text (`large`):
   `flutter test --update-goldens test_shots/shots_test.dart` (add
   `--name '^(scenario)_'` for one scenario, `--dart-define=SHOT_ACCENT=Blue` for another
   accent). The PNGs go to `test_shots/out/` (ignored by git); see `test_shots/README.md`.
4. Compare the renders before and after. Every element should be where it was, unless the owner
   asked for the change and it's logged.
5. The widget-code column of the styling grep (§6) stays at zero.

---

## 9. On-device checklist (for the owner)

None of these could be checked without a device. They're still open.

- [ ] **Profile build:** scroll Home and the podcast Inbox quickly. Steady scroll should drop no
      frames (none over 16 ms on a mid-range phone).
- [ ] **OLED smearing:** scroll Home and lists quickly. Pure black next to `#16181C` surfaces
      (Home tiles, the Riff Wave card, the mini player) should not smear noticeably. If it does,
      `surface1` can go up a step.
- [ ] **Readability:** at Android font scale 130%, the `#71767B` metadata is still readable and
      nothing is badly truncated.
- [ ] **Accents:** all six (Green, Blue, Violet, Crimson, Amber, Cyan) look right, and black
      `onAccent` text stays readable on each. If one is too dark, only that accent switches to
      white `onAccent`, in the theme.
- [ ] **Cover-coloured player:** white text stays readable on very light and very saturated covers.
- [ ] **Rail:** same position, width (47) and items; the active item is clearly in the accent.
- [ ] **Skip-ad pill:** it appears on an ad chapter and skips it. SponsorBlock segments still skip.
- [ ] **System bars:** no content is hidden behind the system navigation bar, with gesture and
      3-button navigation.
- [ ] **Haptics:** a long press on a song or tile gives a medium tap. Play next, add to playlist
      and starting a download give a light tap. The rail gives a selection click.

---

## 10. Notes
- X doesn't publish its exact pixel values. The original plan marked each value as measured from
  x.com's CSS or estimated. The values above are now the ones in the code, tuned on renders.
  `#2F3336` and `#333639` both appear as X's border grey: Riff uses `#2F3336` for hairlines and
  `#333639` for the sheet handle.
- X's 2026 app uses translucent, blurred bars. Riff leaves them out on purpose: on a pure-black
  OLED UI the blur is barely visible, it costs GPU time, and content would have to scroll under
  the chrome. The restyle also removed the one blurred wash (behind the podcast show header).
- Inter stands in for X's proprietary Chirp: very close, not identical.
- Records: `docs/redesign/AUDIT.md` (Phase 0 audit), `SKIPPED.md` (every deviation, with the
  owner's requests), `QA.md` (Phase 9), `V2.md` (redesign v2). Screenshots are in `baseline/`,
  `phase1/`–`phase8/` and `after/`.
