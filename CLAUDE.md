# CLAUDE.md

Project instructions for agents live in `AGENTS.md` (toolchain, lint, tests,
builds). Read it first.

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
