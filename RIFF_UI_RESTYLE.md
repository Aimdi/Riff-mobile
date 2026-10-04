# Riff-mobile — X-Style UI Restyle (visual only)

Target: make Riff-mobile *look and feel* like the 2026 X app ("Lights out" theme) while keeping
Riff's pure-black OLED background and green accent. **Nothing moves.** Every screen keeps its
current elements, in their current positions, in their current order. Only how they look changes.

Based on the repo state around 1.7.133 (PR #115). Phase 0 verifies against the current code.

---

## How to use this file

1. Put this file in the repo root as `RIFF_UI_RESTYLE.md`.
2. Paste the **Rules** block (section 3) into `CLAUDE.md`.
3. Run one phase per Claude Code session:
   > Read RIFF_UI_RESTYLE.md. Do Phase N only. Follow the Rules. Stop when the acceptance checks pass and report the results.
4. One phase = one branch/PR. Review screenshots before merging the next phase.

---

## 1. Scope

### In scope (allowed changes)
- Colors, typography (font family, sizes, weights, line heights), letter spacing
- Padding, gaps, margins, section spacing, row heights, artwork sizes, corner radii
- Dividers/hairlines, borders, removal of shadows/elevation, card backgrounds
- Icon style (outline vs. filled), icon sizes, icon colors
- Styling of buttons, pills, chips, switches, sliders, progress bars, text fields, tabs
- Styling of bottom sheets, dialogs, menus, snackbars, loading states (spinners/skeletons)
- Press/hover/selected states, animation durations and curves, haptic feedback on existing actions

### Out of scope (must NOT change)
- **Position of any element** on any screen. No moving, adding, removing, or reordering UI elements.
- **The left side rail stays exactly where it is:** same width (`kRailWidth` = 47), same items, same order,
  same behavior. No bottom tab bar. No drawer. No new tabs.
- **Home section set and order:** `buildHomeSections` output and its unit tests stay unchanged.
- Component arrangement: a carousel stays a carousel, a grid stays a grid, a card keeps its internal
  element order, centered stays centered, left-aligned stays left-aligned.
- Mini player position, `SlidingUpPanel` behavior, routing (`Get.to`), screen structure.
- No hide-on-scroll chrome, no new pills/banners, no new settings.
- All logic: playback, queue, downloads, RSS + YouTube podcasts, chapter ad-skip, SponsorBlock,
  sync, Android Auto, Hive `AppPrefs` persistence.

**If a spec line below would require moving, adding, or removing an element, skip it and log it in
`docs/redesign/SKIPPED.md` with the reason.** Do not improvise layout changes.

---

## 2. Design language: "X Lights out, Riff green"

1. Content sits directly on `#000000`. No gray cards behind lists, no elevation, no shadows.
2. Structure comes from **1-physical-pixel hairlines** (`#2F3336`) and spacing, not boxes.
3. Three text levels only: primary `#E7E9EA`, secondary `#71767B`, accent (interactive only).
4. Icons: **outline when inactive, filled when active.**
5. Green (accent) is used *only* for: active navigation icon, play buttons, progress, toggled-on
   states, primary buttons, links/text buttons, selected chips, the Skip-ad pill, snackbars, spinners.
   Nothing decorative.
6. Dense, bold typography: 15 px body, 800-weight headers, tight line heights.
7. Press feedback is a flat highlight (`#202327`), no ink ripple splash.

---

## 3. Rules (paste into CLAUDE.md)

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

---

## 4. Design tokens

Confidence labels: **[M]** measured from x.com's Lights-out CSS (widely mirrored in community
recreations), **[E]** estimate from X conventions — tune by eye on device, **[R]** existing Riff value,
read it from code.

### 4.1 Colors

| Token | Value | Maps to | Use |
|---|---|---|---|
| `bg` | `#000000` [M] | `colorScheme.surface`, `scaffoldBackgroundColor` | All backgrounds, rail, headers, player |
| `surface1` | `#16181C` [M] | `colorScheme.surfaceContainerLow` | Sheets, dialogs, menus, skeleton base, Riff Wave card, grid tiles |
| `surface2` | `#202327` [E] | `colorScheme.surfaceContainerHigh` | Pressed/highlight state, skeleton pulse, switch off-track |
| `divider` | `#2F3336` [M] | `colorScheme.outlineVariant`, `dividerColor` | Hairlines, card borders, chip borders, inactive slider track |
| `outlineStrong` | `#536471` [E] | `colorScheme.outline` | Outline-button border, switch off-outline |
| `textPrimary` | `#E7E9EA` [M] | `colorScheme.onSurface` | Titles, body, active icons (non-nav) |
| `textSecondary` | `#71767B` [M] | `colorScheme.onSurfaceVariant` | Metadata, inactive icons, timestamps, inactive tab labels |
| `accent` | Riff green [R] | `colorScheme.primary` | See §2.5 |
| `onAccent` | `#000000` [E] | `colorScheme.onPrimary` | Text/icons on accent fills |
| `accentMuted` | accent @ 12% over black [E] | `RiffColors.accentMuted` (ThemeExtension) | Selected chip fill, now-playing row tint |
| `handle` | `#333639` [M] | `RiffColors.handle` | Sheet drag handle |
| `barrier` | `#5B7083` @ 40% [M] | `RiffColors.barrier` | Modal barrier behind sheets/dialogs |
| `danger` | `#F4212E` [M] | `colorScheme.error` | Destructive actions, errors |

- Set `surfaceTint: Colors.transparent` (in the theme file only) so M3 elevation never tints surfaces gray.
- Contrast: `#E7E9EA` on black ≈ 17.2:1; `#71767B` on black ≈ 4.58:1 (just passes WCAG AA).
  **Never put `textSecondary` body text on `surface1` or lighter.**
- Accent variants (Blue/Violet/Crimson/Amber) are resolved from the existing theme setting; only
  `primary`, `accentMuted` derive from it.

### 4.2 Spacing (align existing `RiffSpacing` to this scale; keep existing names, add missing ones)

```dart
abstract class RiffSpacing {
  static const double unit = 4;
  static const double xxs = 0.5 * unit; // 2
  static const double xs  = 1 * unit;   // 4
  static const double sm  = 2 * unit;   // 8
  static const double md  = 3 * unit;   // 12
  static const double lg  = 4 * unit;   // 16  ← screen gutter
  static const double xl  = 5 * unit;   // 20
  static const double xxl = 6 * unit;   // 24
  static const double x3l = 8 * unit;   // 32  ← Home section gap
}
```

| Usage | Value |
|---|---|
| Screen gutter (left/right content margin) | 16 [E] (replaces the 12dp gutters from 1.7.108) |
| List row padding | 16 horizontal, 12 vertical [E] |
| Artwork → text gap | 12 [E] |
| Title → subtitle gap | 2 [E] |
| Section header → content | 12 [E] |
| Home section gap (top of each section) | 32 [E] (replaces the 24 + 48 rhythm) |
| Chip gap | 8 [E] |

### 4.3 Radii

| Token | Value | Use |
|---|---|---|
| `xs` | 4 | Song-row thumbnails, mini-player art |
| `sm` | 8 | Album/playlist art, grid tiles, full-player art, snackbars |
| `lg` | 16 | Riff Wave card, sheet top corners, dialogs |
| `pill` | 999 | Buttons, chips, search field, Skip-ad pill |

### 4.4 Sizes

| Element | Value |
|---|---|
| Song/episode row artwork | 48 [E] |
| Mini-player artwork | 40 [E] |
| Album/playlist card artwork (shelves) | keep current width [R]; only radius/typography change |
| Header icon | 22 [E] |
| Row trailing icon (⋮, download, etc.) | 20, `textSecondary` [E] |
| Rail icon | 24 [E] |
| Icon-button hit area | 40 [E] (48 where it already is 48 — don't shrink touch targets) |
| Primary/outline button height | 36 compact, 40 default [E] |
| Chip height | 32 [E] |
| Search field height | 40 [E] |
| Progress track (full player) | 2 [E]; thumb 12, shown only while dragging |
| Sheet handle | 36 × 4 [E] |
| Skip-ad pill | 36 tall [E] |

### 4.5 Typography — Inter, bundled as assets (no runtime font fetching)

X uses Chirp (proprietary, not licensable). Inter (SIL OFL) is the closest free match.
Bundle weights 400, 500, 600, 700, 800 under `assets/fonts/` and set `fontFamily: 'Inter'`.

| TextTheme slot | Size / line height | Weight | Default color | Used for |
|---|---|---|---|---|
| `headlineSmall` | 24 / 28 | 800 | primary | Large page titles |
| `titleLarge` | 20 / 24 | 800 | primary | Page header titles, section headers |
| `titleMedium` | 15 / 20 | 700 | primary | Row titles, card titles, names |
| `bodyLarge` | 15 / 20 | 400 | primary | Body, descriptions, settings titles |
| `bodyMedium` | 13 / 16 | 400 | secondary | Metadata, subtitles, timestamps |
| `labelLarge` | 15 / 20 | 700 | primary | Buttons, active tab labels |
| `labelMedium` | 14 / 18 | 600 | primary | Chips |
| `labelSmall` | 12 / 16 | 600 | secondary | Captions, times, pills |
| Player title (`headlineSmall` variant via theme extension or `titleLarge` override) | 22 / 28 | 800 | primary | Full-player title |

Letter spacing 0 everywhere (Inter is already tight). If a slot is used anywhere in the app that
isn't defined above, define it — never let a slot fall back to Material's default font.

### 4.6 Icons
- Outline glyph = inactive/off; filled glyph = active/on (e.g. `Icons.favorite_border` → `Icons.favorite`).
- Default icon color `textPrimary`; metadata/trailing icons `textSecondary`; toggled-on icons `accent`.
- Keep the existing icon set; only swap outline/filled variants and sizes.

### 4.7 Motion & haptics

| Item | Value |
|---|---|
| Press highlight | 100 ms, `surface2`, `splashFactory: NoSplash.splashFactory` |
| Selected-state / tab indicator change | 200 ms, `Curves.easeOutCubic` |
| Sheet open | 250 ms |
| Page transition | keep the existing transition type; set duration 250 ms |
| Skip-ad pill appear | 200 ms fade + slide from 8 px below |

Haptics on *existing* actions only:
- `HapticFeedback.selectionClick()` — rail item tap, tab change, chip select
- `HapticFeedback.lightImpact()` — like, add to playlist/queue, download start
- `HapticFeedback.mediumImpact()` — long-press menu open, pull-to-refresh trigger
- Never `heavyImpact`.

---

## 5. Component specs

### 5.1 Hairlines
`DividerThemeData(color: divider, thickness: 0, space: 1)` — thickness 0 renders exactly one
physical pixel. Borders: `BorderSide(color: divider, width: 0)`.

### 5.2 List rows (songs, search results, library items)
Prefer `ListTileThemeData` in the theme; only use a shared row widget where `ListTile` can't express the layout.
- Padding 16h / 12v, artwork 48 radius 4, gap 12
- Title `titleMedium` (15/700) 1 line ellipsis; subtitle `bodyMedium` (13 secondary) 1 line
- Trailing ⋮ 20 `textSecondary`
- Press: `surface2` highlight, no ripple
- Now playing: title in `accent` + small accent equalizer glyph if the row already shows a now-playing indicator
- Separators: **inset hairline** (starts at the text, i.e. 16 + 48 + 12 = 76 from the left) for
  track lists in album/playlist/library; **full-width hairline** for search results, episode lists, settings.
  If the list currently has no separators and adding one changes item extents in a way that breaks
  tests, use full-width hairlines drawn inside the row's bottom edge.

### 5.3 Cards on shelves (albums, playlists, artists, "Similar to you")
- No card background, no border, no elevation
- Artwork radius 8 (artists: keep circular)
- Title `titleMedium` 1 line, subtitle `bodyMedium` 1 line, artwork → title gap 8
- Keep current card width and shelf scroll behavior

### 5.4 Section headers
- `titleLarge` (20/800) `textPrimary`, gutter 16
- Existing "See all"/"More" action → text button 15/700 `accent`, no icon unless one exists already
- 12 to content; Home sections separated by a full-width hairline + 32 top gap

### 5.5 Buttons
| Type | Style |
|---|---|
| Primary (`FilledButton`) | Pill, accent fill, `onAccent` 15/700, height 36/40, padding 16h, no elevation |
| Secondary (`OutlinedButton`) | Pill, transparent, 1px `outlineStrong` border, `textPrimary` 15/700 |
| Text (`TextButton`) | `accent` 15/700, no background |
| Icon (`IconButton`) | 40 hit area, icon 20–22, press = circular `surface2` highlight |
| FAB (only if one already exists) | 56 circle, accent fill, `onAccent` icon 24, no elevation |

### 5.6 Chips (Riff Wave stations, genre chips, filters)
- Height 32, pill radius, padding 12h, `labelMedium` (14/600)
- Unselected: transparent fill, 1px `divider` border, `textPrimary`
- Selected: `accentMuted` fill, 1px `accent` border, `accent` text
- No checkmark icon unless one exists already

### 5.7 Tabs (existing tab strips only — don't add tabs)
- Label 15/700 `textPrimary` when active, 15/500 `textSecondary` when inactive
- Indicator: 4 px tall, fully rounded, `accent`, width = label width
- Hairline under the strip; no tab background color; `NoSplash`

### 5.8 Inputs
- Search field: `surface1` fill, pill radius, height 40, no border; focused: 1px `accent` border;
  placeholder 15/400 `textSecondary`; leading search icon 20 `textSecondary`
- Other text fields: transparent, 1px `divider` border radius 4, focused 2px `accent`, label `textSecondary`

### 5.9 Switches, sliders, progress
- Switch on: track `accent`, thumb `onAccent`; off: track `surface2`, outline `outlineStrong`, thumb `textSecondary`
- Slider: active `accent`, inactive `divider`, thumb `accent` 12
- Linear progress: 2–3 px, `accent` on `divider`; circular spinner: `accent`, stroke 2.5, size 24
- `RefreshIndicator` (where it already exists): `color: accent`, `backgroundColor: surface1`

### 5.10 Bottom sheets & menus (`lib/ui/widgets/riff_sheet.dart`)
- Background `surface1`, top radius 16, barrier `#5B7083` @ 40%
- Handle 36 × 4 `handle`, 8 from top
- Rows: min height 52, padding 16h, icon 22 `textPrimary`, label 15/400 `textPrimary`;
  destructive rows `danger`; section separators = hairline
- Sheet title (if any) `titleLarge`

### 5.11 Dialogs
- Background `surface1`, radius 16, barrier `#5B7083` @ 40%
- Title `titleLarge`, body `bodyLarge` in `textPrimary` (not `textSecondary`: secondary gray on
  `surface1` fails the contrast rule in §4.1)
- Actions: pill buttons per §5.5, keep existing button order

### 5.12 Snackbars
- Floating, margin 16, radius 8, `accent` fill, text 15/600 `onAccent`, action 15/800 `onAccent`

### 5.13 Loading skeletons (only where a loading placeholder already exists)
- If the project's Dart SDK ≥ 3.7: `skeletonizer` (^3.0.0) with base `surface1`, highlight `surface2`.
- Otherwise (Flutter 3.24 ships Dart 3.5): a simple in-house skeleton — `surface1` boxes with the
  real widgets' radii, opacity pulse 0.5 ↔ 1.0 over 1200 ms. **Do not upgrade Flutter for this.**
- Keep spinners where the app shows spinners today; just restyle them (§5.9).

---

## 6. Phases

### Phase 0 — Audit + baseline (no visual changes)
Do:
1. Record Flutter/Dart versions (`pubspec.yaml`, `.metadata`, `flutter --version`).
2. Find where `ThemeData` is built, how Pitch Black + accent variants are stored (Hive `AppPrefs`
   keys), and the exact hex of the green accent.
3. Count hardcoded styling per file:
   `grep -rnE "Color\(0x|Colors\.|fontSize:|fontWeight:|EdgeInsets\.fromLTRB" lib/`
4. Map every screen and its file: Home (and each section widget: Jump back in, Riff Wave + chips,
   Speed dial / 6-tile grid, Quick picks, personalized, Your week, editorial, Explore more,
   Similar to you), Search, Library, artist/album/playlist, mini player, full player
   (Standard/Gesture), lyrics, queue, Podcasts (inbox, show page, episode), Audiobooks, Settings,
   Stats/Rewind, the left rail widget, `riff_sheet.dart`, dialogs, snackbars.
5. Identify which widget is the "6-tile grid" and which builds "Similar to you".
6. Run the screenshot harness for every scenario on phone / small phone / tablet and save to
   `docs/redesign/baseline/`.

Deliver: `docs/redesign/AUDIT.md` + baseline screenshots. Commit `docs: restyle audit + baseline`.

Accept: AUDIT.md lists SDK versions, accent hex, theme file path, rail widget path,
hardcoded-styling counts, and the screen → file map.

### Phase 1 — Tokens, theme, font
Do:
1. Create `lib/ui/theme/riff_tokens.dart`: `RiffPalette` constants (§4.1), extend existing
   `RiffSpacing` / `RiffSizes` (§4.2, §4.4), `RiffRadii` (§4.3), `RiffDurations` (§4.7).
2. Create a `RiffColors` `ThemeExtension` for `accentMuted`, `handle`, `barrier`, `surface2` if not
   mapped, with `copyWith`/`lerp`.
3. Build `RiffTheme.dark(Color accent)`: `useMaterial3: true`, `ColorScheme` mapping per §4.1,
   `surfaceTint: Colors.transparent`, Inter `TextTheme` per §4.5, `DividerThemeData` (§5.1),
   `ListTileThemeData` (§5.2), button themes (§5.5), `ChipThemeData` (§5.6), tab bar theme (§5.7),
   `InputDecorationTheme` (§5.8), switch/slider/progress themes (§5.9), `BottomSheetThemeData`
   (§5.10), `DialogTheme` (§5.11), `SnackBarThemeData` (§5.12), `IconThemeData`,
   `splashFactory: NoSplash.splashFactory`, `highlightColor: surface2`. Use the theme class names
   your Flutter version supports (e.g. `TabBarTheme` vs `TabBarThemeData`).
4. Bundle Inter (400/500/600/700/800) in `assets/fonts/`, register in `pubspec.yaml`.
5. Wire into `GetMaterialApp` so all five accent variants still work.

Don't: touch any screen widget yet.

Accept: app builds; all five accents render; tests green; screens show the new font/colors only
where they already read from the theme.

### Phase 2 — Migrate hardcoded styling to the theme
Do: replace hardcoded `Color`, `Colors.*`, inline `TextStyle` sizes/weights, magic padding numbers,
and `EdgeInsets.fromLTRB` with theme/tokens, ≤10 files per commit. Remove per-widget styling that
the component themes from Phase 1 now cover (delete it at the call site; don't wrap it).

Don't: change any widget's position, order, or presence.

Accept: `grep -rnE "Color\(0x|Colors\." lib/ui | grep -v lib/ui/theme/` → 0 hits (or each remaining
hit documented in AUDIT.md with a reason); no inline `fontSize:` in `build` methods; tests green;
screenshots match baseline layout.

### Phase 3 — Left rail + page headers
Rail (same position, width 47, same items, same order, same label setting):
- Background `#000000`; right edge 1-px hairline `divider`
- Inactive: outline glyph, 24, `textPrimary`
- Active: filled glyph, 24, `accent`; no pill/indicator background (`indicatorColor: transparent`
  if it's a `NavigationRail`)
- If labels are shown today: 11/600, active `accent`, inactive `textSecondary`
- Press: 40-px circular `surface2` highlight; `HapticFeedback.selectionClick()` on tap
- Keep tooltips/Semantics labels

Page headers (every screen; same items in same places):
- Background `#000000`, title `titleLarge` (20/800), icons 22 outline `textPrimary`
- Bottom hairline `divider` that appears only when content is scrolled under the header
  (`AppBar.scrolledUnderElevation: 0` + `shape`/`notificationPredicate`, or the equivalent in
  `RiffPageHeader`); fade 200 ms

Accept: rail widget tests unchanged and green; rail width/items/order identical to baseline
screenshots; no header element moved.

### Phase 4 — Home, restyled in place
Sections keep their order and content. `buildHomeSections` and its unit tests are not modified.
- All sections: header per §5.4; full-width hairline between sections; 32 top gap; 16 gutter.
- **Jump back in / personalized / Your week / editorial / Explore more / Similar to you:**
  shelf cards per §5.3.
- **Riff Wave + chips:** keep the card and its internal layout. Card: `surface1`, radius 16,
  1-px `divider` border, no shadow. Title 17/800 `textPrimary` (define as a theme extension style),
  subtitle `bodyMedium`, play button = accent circle (keep its current size) with `onAccent` icon.
  Station chips per §5.6.
- **Speed dial / 6-tile grid:** keep 2×3 (or current) arrangement and tile size. Tiles `surface1`,
  radius 8, no shadow, no gradient overlay; artwork radius 4; title 13/700 max 2 lines; now-playing
  tile shows an accent equalizer glyph only if a now-playing indicator exists today.
- **Quick picks:** keep the carousel/pages. Rows inside styled per §5.2 (no separators inside
  carousel pages unless they exist today).
- Home header: per Phase 3 headers.

Accept: `buildHomeSections` tests untouched and green; Home screenshots show identical section
order and element positions vs. baseline; only styling differs.

### Phase 5 — Lists: Search, Library, artist, album, playlist, queue
- All song/item rows per §5.2 with the separator rule.
- Search field per §5.8; result-type chips per §5.6; recent searches as rows per §5.2.
- Existing tab strips (e.g. Library) per §5.7.
- Album/playlist headers: artwork radius 8, title `headlineSmall`, metadata `bodyMedium`,
  existing action buttons per §5.5 (Play = primary, others = outline/icon), same positions.
- Artist page: circular avatar kept, name `headlineSmall`, buttons per §5.5.
- Queue: rows per §5.2, current track in `accent`, drag handle 20 `textSecondary`.
- Loading states per §5.13.

Accept: no screen in this phase gains/loses/reorders elements; analyze + tests green.

### Phase 6 — Mini player + full player
Mini player (same position, height, element order):
- Background `#000000` with top hairline `divider` (or `surface1` if it is a floating card today —
  keep its floating/docked form)
- Artwork 40 radius 4; title 15/700; artist 13 `textSecondary`
- Play/pause 28 `textPrimary`; next 24 `textPrimary`
- If it shows progress today: 2-px `accent` line on `divider` track along its existing edge

Full player (same layout and alignment as today):
- Background `#000000`; if dynamic album color is used, limit it to a top gradient ≤20% opacity
- Artwork radius 8, no shadow (or the existing shadow at ≤20% black)
- Title 22/800 `textPrimary`, artist 15/400 `textSecondary`
- Progress: track 2 px `divider`, active `accent`, thumb 12 `accent` visible only while dragging,
  times `labelSmall`
- Play/pause: accent circle (keep current size) with `onAccent` icon
- Prev/next/shuffle/repeat: outline glyphs `textPrimary`; toggled on = `accent`
- Action row (like, add, lyrics, queue, share — whichever exist): 20 `textSecondary`; toggled on =
  filled `accent` + `lightImpact`
- Lyrics: current line 20/800 `textPrimary`, other lines 20/800 `textSecondary` @ 60%

Don't: touch `PlayerController`, `SlidingUpPanel` config, or gesture handling.

Accept: playback, seek, queue, lyrics, gestures behave as before; layout matches baseline.

### Phase 7 — Podcasts + Audiobooks + Skip-ad pill
- Episode rows (keep element order): artwork 48 radius 8; title `titleMedium` max 2 lines;
  metadata line (show · date · duration) `bodyMedium`; description (if shown) `bodyLarge` max 3 lines;
  existing actions as 20-px `textSecondary` icons, toggled `accent`; an existing Play control
  becomes a pill (§5.5 outline style, `labelLarge`) showing remaining time if it shows it today;
  episode progress (if shown) 2-px `accent` on `divider`. Full-width hairline between episodes.
- Show page header (same layout): artwork radius 8, title `headlineSmall`, author `bodyMedium`;
  Subscribe = primary pill, Subscribed = outline pill.
- Audiobooks: same rules as episodes/shelves.
- **Skip-ad pill (same position):** 36 tall, pill radius, `accent` fill, `onAccent` text 13/700 +
  skip icon 16; appear 200 ms fade + 8-px slide-up.

Don't: touch chapter parsing, ad-chapter detection, auto-skip, or SponsorBlock logic.

Accept: add/keep a widget test asserting the Skip-ad pill still appears for an ad chapter; RSS and
YouTube episodes play; SponsorBlock segments still skip.

### Phase 8 — Sheets, dialogs, menus, snackbars, Settings, Stats, motion, haptics
- `riff_sheet.dart` and every long-press menu per §5.10
- Dialogs per §5.11, snackbars per §5.12
- Settings: rows min 52, title `bodyLarge`, subtitle `bodyMedium`, switches per §5.9, group
  headers `titleLarge`, hairlines between groups (positions unchanged)
- Stats/Rewind: keep layouts; apply typography, colors (charts: accent for the primary series,
  `textSecondary` for axes/labels, `divider` for gridlines)
- Motion durations per §4.7; haptics map per §4.7 on existing actions only
- Edge to edge: verify transparent status/navigation bars with light icons (existing
  `AnnotatedRegion`) and that no last list item is hidden behind system bars

Accept: every sheet/dialog/snackbar matches spec; no new settings added; tests green.

### Phase 9 — QA
1. `flutter analyze` clean; `flutter test --exclude-tags live` green.
2. Screenshot harness for all scenarios on phone / small phone / tablet → `docs/redesign/after/`.
3. Compare to `docs/redesign/baseline/`: **every element must be in the same place**; list any
   deviation and fix it or justify it.
4. Re-run the hardcoded-styling grep from Phase 0 and record the before/after counts.
5. Profile build: scroll Home and the Podcast inbox; target no frames > 16 ms in steady scroll on a
   mid-range device.
6. Write `docs/redesign/QA.md` with results + the on-device checklist below.

---

## 7. On-device checklist (for the user)
- [ ] OLED smearing: scroll Home and lists quickly; pure black next to `#16181C` surfaces should not
      smear noticeably. If it does on Riff Wave/grid tiles, raise `surface1` slightly or drop tile fills.
- [ ] Readability: Android font scale 130% — `#71767B` metadata still readable, nothing truncated badly.
- [ ] All five accents (Green/Blue/Violet/Crimson/Amber) look right; `onAccent` black stays readable
      on each (if a variant is dark, use white `onAccent` for that variant only, in the theme).
- [ ] Rail: identical position/width/items; active icon clearly green.
- [ ] Skip-ad pill visible on an ad chapter; SponsorBlock skip still works.
- [ ] No content hidden behind the system navigation bar (gesture and 3-button nav).

---

## 8. Notes
- X's exact pixel values are not officially published. Values marked [E] are estimates from x.com
  conventions; tune visually. `#2F3336` vs `#333639` both appear as X's border gray; this plan uses
  `#2F3336` for hairlines and `#333639` for the sheet handle.
- X's 2026 app uses translucent/blurred bars. Deliberately left out: on a pure-black OLED UI the blur
  is barely visible and costs GPU time, and it would require content to scroll under the chrome.
- Inter is a substitute for X's proprietary Chirp; it will look very close, not identical.
