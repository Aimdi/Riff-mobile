# Restyle items skipped or adjusted

Spec lines from `RIFF_UI_RESTYLE.md` that would move, add or remove
elements (or can't be done on this SDK), and what was done instead.

| Phase | Spec item | Why skipped / adjusted | Done instead |
|---|---|---|---|
| 1 | `DividerThemeData(space: 1)` (§5.1) | 12 `Divider()` call sites rely on Material's default 16 dp gap; `space: 1` would pull the content around them together | `thickness: 0` (one physical pixel) and divider colour; gaps unchanged |
| 1 | Page transition 250 ms (§4.7) | `PageTransitionsTheme` builders in Flutter 3.24 fix their own durations; GetX routes pass theirs per call | transition *types* kept as they were (Zoom on Android); duration unchanged |
| 1 | Five accents (§4.1) | The app has six (Cyan as well) | all six kept; each derives `primary`, `secondary`, `accentMuted` |
| 1 | `ColorScheme.primary` = accent only | Most widgets read the accent from `colorScheme.secondary` (Material 2 habit) | accent is both `primary` and `secondary` until Phase 2 moves call sites to `primary` |
| 1 | Material 3 geometry | `useMaterial3: true` changes default toolbar height, list-tile end padding and similar | pinned to the old values in the theme (`toolbarHeight: kToolbarHeight`, list-tile padding 16/16) |
| 1 | Album-colour (dynamic) and light themes | The spec targets Lights out; the other two theme types are user choices with their own palettes | they get the Inter type scale; colours unchanged |
| 3 | Tablet rail (≥ 480 dp): no indicator, accent glyph | It is the `sidebar_with_animation` package, which draws the active glyph white on its floating indicator; dropping the indicator would leave the active item unmarked | bar black, flat surface2 press colours, Inter labels (were a missing font), indicator kept in the accent |
| 3 | Rail glyph 24 for the Songs accordion children | Playlists / Albums / Artists are sub-items under Songs; at 24 they read as top-level destinations | 20 dp (`RiffComponentSizes.railSubIcon`); top-level glyphs are 24 |
| 3 | Scroll-under hairline on the Spotify artist hero | Its pinned bar is a collapsing `SliverAppBar` hero whose title animates into the toolbar; Phase 5 restyles the artist page | unchanged |
| 3 | Hairline directly under the header row where tabs or a sort row sit below it (Library, Podcasts, Audiobooks, Settings, Search) | Content passes under the last pinned row, not the title | the hairline is drawn along the top edge of the scrolling content (`RiffScrollUnder`) |

## Known side effects of Phase 1 (to settle in later phases)

- Inter is a little wider than Plus Jakarta Sans at the same size, so a few
  tight labels wrap where they didn't (e.g. "Add to playlist" in the song
  sheet's action row, making that row a few dp taller). Phase 8 restyles
  the sheet.
- Material 3's input metrics make dense text fields (Settings search) about
  2 dp shorter; Phase 5 sets the search field height explicitly (40).
- Dialogs lose the dark outer frame Material 2 drew around the content card;
  the content keeps its place. Phase 8 restyles dialogs.
