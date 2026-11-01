import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/podcast_inbox_cache.dart';
import '/services/podcast_library.dart';
import '/services/podcast_playback_profile.dart';
import '/services/podcast_progress_service.dart';

/// How many of [shows]' episodes in [inbox] are still waiting: not [done]
/// (played, or archived by the show's Keep latest). [shows] are
/// [podcastShowKey]s: one show's, or a folder's.
int podcastWaitingCount(Iterable<MediaItem> inbox, Set<String> shows,
    {required bool Function(String id) done}) {
  if (shows.isEmpty) return 0;
  final waiting = <String>{};
  for (final e in inbox) {
    final show = podcastShowKey(e);
    if (show == null || !shows.contains(show) || done(e.id)) continue;
    waiting.add(e.id);
  }
  return waiting.length;
}

/// The count of new episodes on a followed show's cover in Subs, as
/// AntennaPod and Pocket Casts show: its episodes the Inbox lists.
class PodcastInboxCounts {
  PodcastInboxCounts._();

  /// Bumped when the Inbox is rebuilt, for Obx.
  static final rev = 0.obs;

  static List<MediaItem>? _inbox;

  /// The Inbox just built: every followed show's recent episodes, played
  /// ones too.
  static void setInbox(List<MediaItem> merged) {
    _inbox = merged;
    rev.value++;
  }

  /// This session's Inbox, else the one saved on the phone (looked for
  /// again while there's none: its box may not be open yet).
  static List<MediaItem> _episodes() {
    _inbox ??= PodcastInboxCache.load(null)?.items;
    return _inbox ?? const [];
  }

  /// Each show's newest episode in the Inbox (its `pubDateMs`), by
  /// [podcastShowKey], for sorting by latest episode.
  static Map<String, int> latestByShow() {
    final latest = <String, int>{};
    for (final e in _episodes()) {
      final show = podcastShowKey(e);
      final pub = e.extras?['pubDateMs'];
      if (show == null || pub is! int || pub <= 0) continue;
      if (pub > (latest[show] ?? 0)) latest[show] = pub;
    }
    return latest;
  }

  /// The Inbox as it lists episodes: not played, not archived by Keep
  /// latest, of a show still followed, newest first (Home, the car).
  static List<MediaItem> waiting() {
    final unfollowed = _unfollowed();
    return [
      for (final e in _episodes())
        if (!PodcastProgressService.isPlayed(e.id) &&
            !PodcastLibrary.isArchived(e.id) &&
            !unfollowed(e))
          e
    ];
  }

  /// Whether an episode's show is no longer followed. The Inbox saved on
  /// the phone is the last one built, so a show unfollowed since (or all
  /// of them) still had its episodes on Home. A list not open yet can't
  /// say, so its shows' episodes stay.
  static bool Function(MediaItem) _unfollowed() {
    Set<String>? keys(String box, String? Function(Map) key) {
      if (!Hive.isBoxOpen(box)) return null;
      return {
        for (final v in Hive.box(box).values)
          if (v is Map)
            if (key(v) case final k?) k
      };
    }

    final feeds =
        keys('PodcastSubs', (v) => podcastShowKeyForFeed('${v['feedUrl']}'));
    final youtube = keys('LibraryPodcasts',
        (v) => podcastShowKeyForYoutube('${v['playlistId'] ?? ''}'));
    return (e) {
      final show = podcastShowKey(e);
      if (show == null) return false;
      final followed = podcastShowKeyIsFeed(show) ? feeds : youtube;
      return followed != null && !followed.contains(show);
    };
  }

  static int count(Set<String> shows) => podcastWaitingCount(
        _episodes(),
        shows,
        done: (id) =>
            PodcastProgressService.isPlayed(id) ||
            PodcastLibrary.isArchived(id),
      );
}
