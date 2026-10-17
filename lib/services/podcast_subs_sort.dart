import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// How Podcasts › Subscriptions lists the shows you follow, like Pocket
/// Casts', AntennaPod's and Apple Podcasts' sort: as they're stored, by
/// name, by their latest episode, or by when you followed them.
enum PodcastSubsSort { standard, name, latestEpisode, recentlyFollowed }

/// What [sortPodcastSubs] looks at for a show: its title, its newest
/// episode and when you followed it (0 when not known).
typedef PodcastSubsSortKey = ({String title, int latestMs, int followedMs});

/// [shows] in [sort]'s order: names A to Z, else newest first with the
/// unknown ones last; ties by name, then as they were.
List<T> sortPodcastSubs<T>(List<T> shows, PodcastSubsSort sort,
    PodcastSubsSortKey Function(T show) keyOf) {
  if (sort == PodcastSubsSort.standard) return shows;
  final keyed = [
    for (var i = 0; i < shows.length; i++) (i, shows[i], keyOf(shows[i]))
  ];
  int byName((int, T, PodcastSubsSortKey) a, (int, T, PodcastSubsSortKey) b) {
    final c = a.$3.title.toLowerCase().compareTo(b.$3.title.toLowerCase());
    return c != 0 ? c : a.$1.compareTo(b.$1);
  }

  int newestFirst(int a, int b) => b.compareTo(a);
  keyed.sort((a, b) {
    final c = switch (sort) {
      PodcastSubsSort.latestEpisode =>
        newestFirst(a.$3.latestMs, b.$3.latestMs),
      PodcastSubsSort.recentlyFollowed =>
        newestFirst(a.$3.followedMs, b.$3.followedMs),
      _ => 0,
    };
    return c != 0 ? c : byName(a, b);
  });
  return [for (final k in keyed) k.$2];
}

/// The chosen [PodcastSubsSort], kept in AppPrefs.
class PodcastSubsOrder {
  PodcastSubsOrder._();

  static const prefKey = 'podcastSubsSort';

  static final sort = Rx<PodcastSubsSort>(_stored());

  static PodcastSubsSort _stored() {
    final raw =
        Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs').get(prefKey) : null;
    return PodcastSubsSort.values.firstWhere((s) => s.name == raw,
        orElse: () => PodcastSubsSort.standard);
  }

  static Future<void> set(PodcastSubsSort s) async {
    sort.value = s;
    if (Hive.isBoxOpen('AppPrefs')) {
      await Hive.box('AppPrefs').put(prefKey, s.name);
    }
  }
}
