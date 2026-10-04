# UI restyle — Phase 9 QA

Final check of the "X Lights out, Riff green" restyle (`RIFF_UI_RESTYLE.md`),
run on top of Phase 8 (1.7.142).

## 1. Analyze and tests

| Check | Result |
|---|---|
| `flutter analyze` | No issues |
| `flutter test --exclude-tags live` | 915 passed (910 before the restyle, plus the hairline header, Skip-ad pill and theme tests) |
| Rail widget test (`test/home/side_rail_test.dart`) | Unchanged, green |
| `buildHomeSections` tests (`test/home/home_feed_builder_test.dart` and friends) | Unchanged, green |
| Skip-ad pill test (`test/podcasts/podcast_skip_pill_test.dart`) | Green |

Device CI (podcast playback on API 31/34/35, release APK on API 34/35, app
tour) passed on every phase PR. On Phase 5, the API 34 podcast run failed
once and passed when re-run. It was the only failure across all phases, on a
test that streams a live podcast feed.

## 2. Screenshots

`docs/redesign/after/` has 119 renders from the screenshot harness: phone
(411 dp), small phone (360 dp), tablet (900 dp), light theme, album-colour
theme and 130% text. That is every baseline scenario plus 7 newer ones, at
the same 1× size as `docs/redesign/baseline/` (112). Every suite renders
without overflow. The settings suite logs a missing-permission-plugin error
from the test environment after the test has finished. That error was there
before the restyle.

## 3. Same place check (baseline → after)

I compared every screen side by side against the baseline. On each one:

- the elements are the same, in the same order;
- the rail has the same width (47), items and order;
- the Home section set and order are the same;
- header buttons are in the same places.

The differences are the deliberate spec values. Each phase logged them in
`SKIPPED.md` / `AUDIT.md`:

| Change | Effect | Why |
|---|---|---|
| 16 dp gutter everywhere (was 12–18) | Content edges move up to 4 dp | §4.2 |
| 4-point spacing grid | Small gaps move 1–4 dp | §4.2 |
| Home section gap 32, header → content 12 | Home sections sit lower | §4.2 / Phase 4 |
| Rail labels 11/600 | Rail items sit slightly higher | Phase 3 |
| Page titles 20/800 on pushed pages (were 26) | Content under them moves up about 6 dp | Phase 3 |
| §5.2 row padding 16/12 | Rows without a fixed extent (album/playlist tracks) are 4 dp taller; rows with fixed extents are unchanged | Phase 5 |
| Settings search 40 dp, flat groups | Groups sit a few dp higher | Phase 8 |
| Chips 32 dp inside the existing 48 dp touch rows | Chip rows keep their height | Phases 4, 5, 7 |

None of these remove, add or reorder an element.

## 4. Hardcoded styling, before and after

`grep -rnE "Color\(0x|Colors\.|fontSize:|fontWeight:|EdgeInsets\.fromLTRB" lib/`

| Pattern | Phase 0 (all `lib/`) | Now (all `lib/`) | Now, real hits in widget code (`lib/ui` outside `lib/ui/theme/` and `theme_controller.dart`) |
|---|---|---|---|
| `Color(0x` | 81 | 92 | 0 |
| `Colors.` | 218 | 175 | 0 |
| `fontSize:` | 212 | 4 | 3 (computed) |
| `fontWeight:` | 191 | 4 | 1 (computed) |
| `EdgeInsets.fromLTRB` | 135 | 0 | 0 |

What the "all `lib/`" numbers still include:

- `Colors.`: names that only end in "Colors" (`RiffColors.of`, `PodcastFolderColors.swatches`), `Colors.transparent`, and the light and album-colour themes.
- `Color(0x`: the theme itself and the data palettes in `lib/ui/theme/palettes/`.

What is left in widget code:

- Three computed font sizes, all documented exceptions: karaoke emphasis in `word_synced_lyrics.dart`, the seconds glyph in `podcast_playback_controls.dart`, and `letter_art.dart`.
- One computed weight, for that same seconds glyph.

## 5. Performance

I couldn't do the profile-build pass (scroll Home and the podcast Inbox,
target no frame over 16 ms) here: there's no device or emulator with a GPU.
It's the first item in the on-device checklist below.

What I checked in code:

- No new blur or `saveLayer` effects. A blurred cover-art wash behind the podcast show header was removed.
- The header hairline repaints only when the scroll-under state flips.
- The skeleton pulse runs on one animation controller per placeholder and stops when animations are off.
- The equalizer in Riff Wave only animates while playing (unchanged).

## 6. On-device checklist (for you)

- [ ] **Profile build:** scroll Home and the podcast Inbox quickly. Steady scroll should drop no frames (no frame over 16 ms on a mid-range phone).
- [ ] **OLED smearing:** scroll Home and lists quickly. Pure black next to `#16181C` surfaces (Riff Wave card, grid tiles) should not smear noticeably. If it does, `surface1` can go up a step, or the tile fills can be dropped.
- [ ] **Readability:** at Android font scale 130%, the `#71767B` metadata is still readable and nothing is badly truncated.
- [ ] **Accents:** all six (Green, Blue, Violet, Crimson, Amber, Cyan) look right, and black `onAccent` text stays readable on each. If one is too dark, that accent alone can switch to white `onAccent` in the theme.
- [ ] **Rail:** same position, width and items as before; the active icon is clearly in the accent.
- [ ] **Skip-ad pill:** it appears on an ad chapter and skips it. SponsorBlock segments still skip.
- [ ] **System bars:** no content is hidden behind the system navigation bar, with both gesture and 3-button navigation.
- [ ] **Haptics:** long-pressing a song or tile gives a medium tap; play next, add to playlist and starting a download give a light tap; the rail gives a selection click.
