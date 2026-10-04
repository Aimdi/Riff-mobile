/// Builds the Home tab's section list from plain data: the fixed order,
/// "each item once", the editorial merges and caps. Pure so it can be
/// unit-tested; the widgets only draw what comes out.
library;

/// The blocks of Home, top to bottom. The order never changes; sections
/// with nothing to show are left out.
enum HomeSection {
  header,
  jumpBackIn,
  riffWave,
  speedDial,
  quickPicks,
  personalized,
  spotify,
  yourWeek,
  editorial,
  exploreMore,
}

/// One thing on Home: a song, album, playlist, artist, mix, show…
/// [key] identifies it across sections (`song:<videoId>`, `album:<id>`…).
class HomeItem<T> {
  const HomeItem(this.key, this.value, {this.hasArt = true, this.altKey});
  final String key;
  final T value;

  /// A second identity across sources (`ta:<title>|<artist>`), so a
  /// Spotify song isn't repeated when the same song is on Home from
  /// YouTube Music.
  final String? altKey;

  /// False when the item has no artwork of its own (empty URL or the
  /// generic placeholder), for the "mostly missing artwork" rule.
  final bool hasArt;
}

/// What a shelf holds; picks the card size.
enum HomeShelfKind {
  collections,
  songs,
  artists,
  videos,
  episodes,
  mixes,
  mixed
}

class HomeShelfData {
  const HomeShelfData({
    required this.id,
    required this.title,
    required this.items,
    this.kind = HomeShelfKind.collections,
    this.kicker,
    this.seeAll = false,
  });

  final String id;
  final String title;
  final List<HomeItem> items;
  final HomeShelfKind kind;

  /// Small line above the title ("Because you played X").
  final String? kicker;

  /// The shelf has a page of its own (chevron in the header).
  final bool seeAll;

  HomeShelfData copyWith(
          {String? title, List<HomeItem>? items, HomeShelfKind? kind}) =>
      HomeShelfData(
        id: id,
        title: title ?? this.title,
        items: items ?? this.items,
        kind: kind ?? this.kind,
        kicker: kicker,
        seeAll: seeAll,
      );
}

class HomeFeedInput {
  const HomeFeedInput({
    this.jumpBackIn = const [],
    this.speedDial = const [],
    this.quickPicks = const [],
    this.personalized = const [],
    this.spotify = const [],
    this.editorial = const [],
    this.hasWeek = false,
    this.hasExplore = false,
    this.hidden = const {},
    this.chartsTitle = 'Charts & hits',
    this.moodTitle = 'For your mood',
  });

  /// Things to resume, most recent first.
  final List<HomeItem> jumpBackIn;

  /// Pins first, then recently played, most recent first.
  final List<HomeItem> speedDial;
  final List<HomeItem> quickPicks;

  /// Riff's own shelves (mixes, "because you played", subscribed shows).
  final List<HomeShelfData> personalized;

  /// Shelves from your Spotify account.
  final List<HomeShelfData> spotify;

  /// The YouTube Music feed, in the order it came.
  final List<HomeShelfData> editorial;
  final bool hasWeek;

  /// The Explore page has something even when no shelf overflows
  /// (YouTube's genre chips), so the button stays.
  final bool hasExplore;

  /// Sections switched off in Settings → Home layout.
  final Set<HomeSection> hidden;
  final String chartsTitle;
  final String moodTitle;
}

class HomeSectionModel {
  const HomeSectionModel(this.section,
      {this.items = const [], this.shelves = const []});
  final HomeSection section;
  final List<HomeItem> items;
  final List<HomeShelfData> shelves;
}

/// Limits and sizes the rules use.
class HomeFeedRules {
  HomeFeedRules._();
  static const jumpBackInMax = 4;
  static const speedDialPerPage = 9;
  static const speedDialPages = 3;
  static const quickPicksMax = 12;
  static const editorialMax = 4;
  static const editorialMinItems = 4;
  static const personalizedMinItems = 1;
  static const shelfMaxItems = 20;
}

/// Jump back in tiles: one fills the row; 2–4 make the grid, and an odd
/// count above one drops the last so the grid has no hole.
List<T> jumpBackInTiles<T>(List<T> items) {
  final capped = items.take(HomeFeedRules.jumpBackInMax).toList();
  if (capped.length > 1 && capped.length.isOdd) capped.removeLast();
  return capped;
}

/// Speed dial pages: with fewer than a full page there is one page and no
/// dots; otherwise up to three pages of nine.
int speedDialPageCount(int items) {
  if (items <= 0) return 0;
  final pages = (items / HomeFeedRules.speedDialPerPage).ceil();
  return pages.clamp(1, HomeFeedRules.speedDialPages);
}

/// "Today's Biggest Hits" → "Today's biggest hits", "QUICK PICKS" →
/// "Quick picks". Titles that already have a lower-case word ("Similar to
/// Taylor Swift") are left alone so names keep their capitals; acronyms
/// (DJ, R&B, 2000s) stay as they are.
String homeSentenceCase(String title) {
  final t = title.trim();
  if (t.isEmpty) return t;
  final words = t.split(RegExp(r'\s+'));
  final letters = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');
  final lettered = words.where((w) => letters.hasMatch(w)).toList();
  if (lettered.isEmpty) return t;
  bool isUpper(String w) => w == w.toUpperCase() && w != w.toLowerCase();
  bool startsUpper(String w) {
    final m = letters.firstMatch(w);
    if (m == null) return false;
    final c = w[m.start];
    return c == c.toUpperCase() && c != c.toLowerCase();
  }

  final allCaps = lettered.every(isUpper) &&
      t.replaceAll(RegExp(r'[^A-Za-z]'), '').length > 3;
  final titleCase = lettered.every(startsUpper);
  String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  if (allCaps) return cap(t.toLowerCase());
  if (!titleCase) return cap(t);
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    // Acronyms (two or more capitals, like "DJ", "R&B", "UK") keep theirs.
    final acronym =
        isUpper(w) && w.replaceAll(RegExp(r'[^A-Za-z]'), '').length >= 2;
    out.add(i == 0 || acronym ? w : w.toLowerCase());
  }
  return cap(out.join(' '));
}

enum HomeEditorialKind { plain, personal, charts, mood, throwback }

bool _hasAny(String t, List<String> needles) => needles.any(t.contains);

/// Sorts a YouTube shelf title into the editorial rules' buckets.
HomeEditorialKind classifyEditorialShelf(String title) {
  final t = title.toLowerCase();
  if (t.contains('throwback')) return HomeEditorialKind.throwback;
  if (_hasAny(t, const [
    'new release',
    'similar to',
    'mixed for you',
    'made for you',
    'for you',
    'listen again',
    'from your library',
    'forgotten favo',
    'because you',
    'your favo',
    'recommended',
    'mixtape',
    'my supermix',
  ])) {
    return HomeEditorialKind.personal;
  }
  if (_hasAny(t, const [
    'chart',
    '100%',
    'biggest hits',
    'top hits',
    'top songs',
    'top 50',
    'top 100',
    'trending',
    'top music videos',
    'hot list',
  ])) {
    return HomeEditorialKind.charts;
  }
  if (_hasAny(t, const [
    'breakfast',
    'brunch',
    'morning',
    'afternoon',
    'evening',
    'tonight',
    'night',
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'weekend',
    'out of bed',
    'wake up',
    'mood',
    'workout',
    'chill',
    'relax',
    'focus',
    'sleep',
    'feel good',
    'feel-good',
    'energy',
    'energi',
    'commute',
    'party',
    'romance',
    'sad ',
    'dinner',
    'lunch',
    'cozy',
    'calm',
  ])) {
    return HomeEditorialKind.mood;
  }
  return HomeEditorialKind.plain;
}

int _missingArt(Iterable<HomeItem> items) =>
    items.where((i) => !i.hasArt).length;

/// More than half the covers missing: the shelf looks broken, hide it.
bool shelfArtMostlyMissing(List<HomeItem> items) =>
    items.isNotEmpty && _missingArt(items) * 2 > items.length;

/// Applies the editorial rules: drops Throwback, lifts personal shelves
/// out (returned separately), merges charts and mood shelves into one
/// each (at the first one's place), sentence-cases titles.
({List<HomeShelfData> editorial, List<HomeShelfData> personal})
    applyEditorialRules(
  List<HomeShelfData> shelves, {
  String chartsTitle = 'Charts & hits',
  String moodTitle = 'For your mood',
}) {
  final out = <HomeShelfData>[];
  final personal = <HomeShelfData>[];
  int? chartsAt;
  int? moodAt;
  final chartsItems = <HomeItem>[];
  final moodItems = <HomeItem>[];
  final chartsKinds = <HomeShelfKind>{};
  final moodKinds = <HomeShelfKind>{};
  for (final s in shelves) {
    final titled = s.copyWith(title: homeSentenceCase(s.title));
    switch (classifyEditorialShelf(s.title)) {
      case HomeEditorialKind.throwback:
        break;
      case HomeEditorialKind.personal:
        personal.add(titled);
      case HomeEditorialKind.charts:
        if (chartsAt == null) {
          chartsAt = out.length;
          out.add(titled); // placeholder, replaced below
        }
        chartsItems.addAll(s.items);
        chartsKinds.add(s.kind);
      case HomeEditorialKind.mood:
        if (moodAt == null) {
          moodAt = out.length;
          out.add(titled);
        }
        moodItems.addAll(s.items);
        moodKinds.add(s.kind);
      case HomeEditorialKind.plain:
        out.add(titled);
    }
  }
  HomeShelfData merged(HomeShelfData first, String title, List<HomeItem> items,
          Set<HomeShelfKind> kinds) =>
      HomeShelfData(
        id: '${first.id}+',
        title: title,
        items: _uniqueByKey(items),
        kind: kinds.length == 1 ? kinds.first : HomeShelfKind.mixed,
      );
  if (chartsAt != null) {
    out[chartsAt] =
        merged(out[chartsAt], chartsTitle, chartsItems, chartsKinds);
  }
  if (moodAt != null) {
    out[moodAt] = merged(out[moodAt], moodTitle, moodItems, moodKinds);
  }
  return (editorial: out, personal: personal);
}

bool _isSeen(HomeItem i, Set<String> seen) =>
    seen.contains(i.key) || (i.altKey != null && seen.contains(i.altKey));

void _mark(HomeItem i, Set<String> seen) {
  seen.add(i.key);
  if (i.altKey != null) seen.add(i.altKey!);
}

List<HomeItem> _uniqueByKey(Iterable<HomeItem> items) {
  final seen = <String>{};
  final out = <HomeItem>[];
  for (final i in items) {
    if (_isSeen(i, seen)) continue;
    _mark(i, seen);
    out.add(i);
  }
  return out;
}

/// Items not yet on Home, recording them as shown.
List<HomeItem> _claim(Iterable<HomeItem> items, Set<String> seen, {int? max}) {
  final out = <HomeItem>[];
  for (final i in items) {
    if (max != null && out.length >= max) break;
    if (i.key.isEmpty || _isSeen(i, seen)) continue;
    _mark(i, seen);
    out.add(i);
  }
  return out;
}

/// Keeps a shelf when it has enough items not shown higher up and its
/// artwork isn't mostly missing.
HomeShelfData? _claimShelf(HomeShelfData s, Set<String> seen, int minItems) {
  final fresh = [
    for (final i in s.items)
      if (i.key.isNotEmpty && !_isSeen(i, seen)) i
  ];
  final unique = _uniqueByKey(fresh).take(HomeFeedRules.shelfMaxItems).toList();
  if (unique.length < minItems || shelfArtMostlyMissing(unique)) return null;
  for (final i in unique) {
    _mark(i, seen);
  }
  return s.copyWith(items: unique);
}

/// The Home tab, top to bottom.
///
/// Claims run in priority order so an item shows once, in its highest
/// place: Jump back in → Speed dial page 1 → Quick picks → the rest of
/// Speed dial → personalized → Spotify → editorial.
List<HomeSectionModel> buildHomeSections(HomeFeedInput data) {
  final seen = <String>{};
  bool shown(HomeSection s) => !data.hidden.contains(s);

  final jump = shown(HomeSection.jumpBackIn)
      ? jumpBackInTiles(
          _uniqueByKey(data.jumpBackIn.where((i) => i.key.isNotEmpty)))
      : const <HomeItem>[];
  // A tile dropped to even the grid is free to show further down.
  for (final i in jump) {
    _mark(i, seen);
  }

  final dialPool = shown(HomeSection.speedDial)
      ? _uniqueByKey(data.speedDial.where((i) => !_isSeen(i, seen))).toList()
      : const <HomeItem>[];
  final firstPage = _claim(dialPool, seen, max: HomeFeedRules.speedDialPerPage);

  final picks = shown(HomeSection.quickPicks)
      ? _claim(data.quickPicks, seen, max: HomeFeedRules.quickPicksMax)
      : const <HomeItem>[];

  final restOfDial = _claim(dialPool.skip(firstPage.length), seen,
      max: HomeFeedRules.speedDialPerPage * (HomeFeedRules.speedDialPages - 1));
  final dial = [...firstPage, ...restOfDial];

  final rules = applyEditorialRules(data.editorial,
      chartsTitle: data.chartsTitle, moodTitle: data.moodTitle);

  final personal = <HomeShelfData>[];
  if (shown(HomeSection.personalized)) {
    // YouTube's personal shelves (New releases, Similar to…) lead.
    for (final s in [...rules.personal, ...data.personalized]) {
      final kept = _claimShelf(s, seen, HomeFeedRules.personalizedMinItems);
      if (kept != null) personal.add(kept);
    }
  }

  final spotify = <HomeShelfData>[];
  if (shown(HomeSection.spotify)) {
    for (final s in data.spotify) {
      final kept = _claimShelf(s, seen, HomeFeedRules.personalizedMinItems);
      if (kept != null) spotify.add(kept);
    }
  }

  final editorial = <HomeShelfData>[];
  var overflow = 0;
  if (shown(HomeSection.editorial)) {
    for (final s in rules.editorial) {
      if (editorial.length >= HomeFeedRules.editorialMax) {
        overflow++;
        continue;
      }
      final kept = _claimShelf(s, seen, HomeFeedRules.editorialMinItems);
      if (kept != null) editorial.add(kept);
    }
  }

  return [
    const HomeSectionModel(HomeSection.header),
    if (jump.isNotEmpty) HomeSectionModel(HomeSection.jumpBackIn, items: jump),
    if (shown(HomeSection.riffWave))
      const HomeSectionModel(HomeSection.riffWave),
    if (dial.isNotEmpty) HomeSectionModel(HomeSection.speedDial, items: dial),
    if (picks.isNotEmpty)
      HomeSectionModel(HomeSection.quickPicks, items: picks),
    if (personal.isNotEmpty)
      HomeSectionModel(HomeSection.personalized, shelves: personal),
    if (spotify.isNotEmpty)
      HomeSectionModel(HomeSection.spotify, shelves: spotify),
    if (data.hasWeek && shown(HomeSection.yourWeek))
      const HomeSectionModel(HomeSection.yourWeek),
    if (editorial.isNotEmpty)
      HomeSectionModel(HomeSection.editorial, shelves: editorial),
    if (overflow > 0 || data.hasExplore)
      const HomeSectionModel(HomeSection.exploreMore),
  ];
}
