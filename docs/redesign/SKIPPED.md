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
| 4 | Speed dial tile title 13/700, artwork radius 4 (§Phase 4) | Speed dial tiles are full-bleed covers with no title today; a title would add an element | tiles on surface1, radius 8, accent now-playing equalizer; `RiffTextStyles.tileTitle` defined for later use |
| 4 | Quick picks rows per §5.2 | Quick picks is a carousel of large cover cards here, not pages of rows | carousel kept; cards on surface1, art radius 8, subtitle bodyMedium |
| 4 | Jump back in / Your week as §5.3 shelf cards (no background) | They are grid tiles and a stats card, not shelf cards; without a background their text floats | surface1 tiles and card, radius 8 |
| 4 | "See all" as a 15/700 accent text button | The control is an icon-only chevron today; a text label would add an element and change the header width | chevron kept, drawn in the accent |
| 4 | Selected station chip | Station chips start playback and have no selected state | the selected look (accentMuted fill, accent border and text) shows while a station is starting |
| 5 | Queue rows 12 dp vertical padding (§5.2) | The queue's fixed 64 dp row extent (`itemExtentBuilder`) would need to grow to 72 | 48 art centred in the 64 dp row (≈8 dp), everything else per §5.2 |
| 5 | Wide album/playlist rows: one-line titles | They are 96 dp rows with 76 dp art; one line would cut long titles that fit today | two lines kept |
| 5 | Queue "Now playing" label in the accent | §2.5 keeps the accent for the playing title and equalizer | label in the secondary colour |
| 5 | Artist/collection header paddings (toolbar 85, avatar box 200/260) | Not on the 4-point scale; snapping them would move the headers | left as they are |
| 6 | Full-player artwork radius 8 | Portrait (standard) and gesture players show the cover full-bleed, fading into the page, not as a framed square | full-bleed kept, no shadow; radius 8 applies to the landscape/desktop art |
| 6 | Outline prev/next glyphs | Material has no outline variant of the skip icons | rounded glyphs in the primary text colour |
| 6 | Heart glyph colours off-state | It is drawn by `favorite_heart_button.dart` (shared with rows) | unchanged until Phase 8; haptic added at the player call sites |
| 6 | Mini player play/pause on desktop | The wide layout's play button is a 58 dp accent circle (a play button, allowed to be accent) | kept; phone mini player uses the plain 28 dp glyph |
| 6 | Spacings off the 4-point scale in the player column (10/14/6/3, landscape 90/10, 65 dp queue strip) | Snapping them would move controls | left as they are |
| 7 | Show header cover-art wash | A blurred art wash behind the show header broke rule 4 (background always black; art tint only in the full player) | removed; header on black |
| 7 | Episode/continue-card spacing | Off-grid values (18, 10, 6, 3) snapped to the 4-point scale | moves rows by a few dp; no fixed extents involved |
| 7 | Show-search result art 48 | Those are wide 72 dp-art rows; 48 would change the row layout | kept at 72 |
| 7 | Now-playing state on Inbox/Queue rows | The episode tile has no now-playing indicator today | not added (the show page rows, which have one, get the accentMuted tint) |
| 7 | Store browse grid titles one line | Fixed-aspect grid; one line would cut titles that fit today | two lines kept |
| 7 | Rating stars and genre/category tiles | Content colours (data palettes), not chrome | kept; only radius/spacing changed |
| 7 | Sheets and dialogs in podcasts/audiobooks | Phase 8 | untouched |

## Known side effects of Phase 1 (to settle in later phases)

- Inter is a little wider than Plus Jakarta Sans at the same size, so a few
  tight labels wrap where they didn't (e.g. "Add to playlist" in the song
  sheet's action row, making that row a few dp taller). Phase 8 restyles
  the sheet.
- Material 3's input metrics make dense text fields (Settings search) about
  2 dp shorter; Phase 5 sets the search field height explicitly (40).
- Dialogs lose the dark outer frame Material 2 drew around the content card;
  the content keeps its place. Phase 8 restyles dialogs.
