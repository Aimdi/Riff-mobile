import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/helper.dart';
import '/ui/player/player_controller.dart';
import '/ui/screens/Podcasts/podcast_queue_controller.dart';
import 'network_kind.dart';
import 'podcast_bookmarks.dart';
import 'podcast_download_service.dart';
import 'podcast_playback_profile.dart';
import 'podcast_progress_service.dart';
import 'podcast_starred.dart';

// ── Keep latest N ─────────────────────────────────────────────────────

/// Choices for "Keep latest": 0 means all episodes.
const keepLatestChoices = [0, 1, 3, 5, 10];

/// Which of a show's episodes to archive when it keeps only the newest
/// [keep] unplayed ones. [idsNewestFirst] is the show's episodes, newest
/// first. Played episodes don't count, and an episode you've started is
/// never archived (it still counts towards [keep]).
List<String> episodesToArchive(
  List<String> idsNewestFirst,
  int keep, {
  required bool Function(String id) isPlayed,
  required bool Function(String id) inProgress,
}) {
  if (keep <= 0) return const [];
  final out = <String>[];
  var kept = 0;
  for (final id in idsNewestFirst) {
    if (isPlayed(id)) continue;
    if (kept < keep) {
      kept++;
      continue;
    }
    if (!inProgress(id)) out.add(id);
  }
  return out;
}

// ── Auto-delete downloads ─────────────────────────────────────────────

enum AutoDeletePolicy { never, immediately, after24h }

AutoDeletePolicy parseAutoDelete(dynamic raw) => AutoDeletePolicy.values
    .firstWhere((p) => p.name == raw, orElse: () => AutoDeletePolicy.never);

/// Whether a downloaded episode finished at [playedAtMs] should go now.
/// Never the episode that's playing.
bool downloadDueForDeletion(AutoDeletePolicy policy, int? playedAtMs,
    int nowMs, {bool isCurrent = false}) {
  if (isCurrent || playedAtMs == null) return false;
  switch (policy) {
    case AutoDeletePolicy.never:
      return false;
    case AutoDeletePolicy.immediately:
      return true;
    case AutoDeletePolicy.after24h:
      return nowMs - playedAtMs >= const Duration(hours: 24).inMilliseconds;
  }
}

// ── New episodes into the queue ───────────────────────────────────────

/// Where a show's new episodes go in the podcast queue, like Pocket Casts'
/// "Add to Up Next": not at all, at the top or at the end.
enum NewEpisodesQueue { off, top, end }

NewEpisodesQueue parseNewEpisodesQueue(dynamic raw) => NewEpisodesQueue.values
    .firstWhere((m) => m.name == raw, orElse: () => NewEpisodesQueue.off);

/// Whether a show's new episodes download by themselves, like AntennaPod's
/// and Pocket Casts' auto download: not at all, on Wi-Fi, or on any
/// connection.
enum NewEpisodesDownload { off, wifi, always }

NewEpisodesDownload parseNewEpisodesDownload(dynamic raw) => NewEpisodesDownload
    .values
    .firstWhere((m) => m.name == raw, orElse: () => NewEpisodesDownload.off);

/// Of a show's [episodes] as the Inbox lists them, the ones new to a job
/// (the queue, downloads), oldest first: not [seen] before, and out after
/// [sinceMs] (when it was switched on). With [seen] null, the first look
/// since, episodes without a date are only noted: there's no telling
/// whether they're new.
List<MediaItem> newEpisodesSince(List<MediaItem> episodes,
    {required Set<String>? seen, required int sinceMs}) {
  final out = <MediaItem>[];
  for (final e in PodcastLibrary.sortNewestFirst(episodes).reversed) {
    if (seen != null && seen.contains(e.id)) continue;
    final pub = e.extras?['pubDateMs'];
    if (pub is int && pub > 0 ? pub > sinceMs : seen != null) out.add(e);
  }
  return out;
}

// ── Library filter chips ──────────────────────────────────────────────

enum EpisodeFilter { fresh, inProgress, queued, downloaded, bookmarked, short }

/// Shorter than this counts as Short.
const shortEpisodeLimit = Duration(minutes: 20);

/// What the filters look at for one episode.
class EpisodeFacts {
  const EpisodeFacts({
    this.played = false,
    this.inProgress = false,
    this.queued = false,
    this.downloaded = false,
    this.bookmarked = false,
    this.duration,
  });
  final bool played;
  final bool inProgress;
  final bool queued;
  final bool downloaded;
  final bool bookmarked;
  final Duration? duration;
}

bool matchesEpisodeFilter(EpisodeFilter? f, EpisodeFacts e) {
  switch (f) {
    case null:
      return true;
    case EpisodeFilter.fresh:
      return !e.played && !e.inProgress;
    case EpisodeFilter.inProgress:
      return e.inProgress;
    case EpisodeFilter.queued:
      return e.queued;
    case EpisodeFilter.downloaded:
      return e.downloaded;
    case EpisodeFilter.bookmarked:
      return e.bookmarked;
    case EpisodeFilter.short:
      final d = e.duration;
      return d != null && d > Duration.zero && d < shortEpisodeLimit;
  }
}

/// Merge episode lists, first occurrence wins (by id), keeping order.
List<MediaItem> uniqueEpisodes(Iterable<Iterable<MediaItem>> lists) {
  final seen = <String>{};
  return [
    for (final l in lists)
      for (final e in l)
        if (seen.add(e.id)) e
  ];
}

// ── Mark all as listened ──────────────────────────────────────────────

/// Episodes "Mark all as listened" changes: the ones not played yet.
List<String> planMarkAllListened(
        Iterable<String> ids, bool Function(String id) isPlayed) =>
    [for (final id in ids) if (!isPlayed(id)) id];

/// What "Mark all as listened" changed, so Undo can put it back.
class ListenedSnapshot {
  ListenedSnapshot(this.ids, this.progress, this.queued);
  final List<String> ids;

  /// Saved positions that marking played removed.
  final Map<String, dynamic> progress;

  /// Up Next entries that marking played removed, with their old index.
  final List<(int, MediaItem)> queued;

  int get count => ids.length;
}

// ── Store ─────────────────────────────────────────────────────────────

/// Per-show library settings (keep latest, auto-delete), the archive of
/// episodes "Keep latest" hid, and the jobs that apply them. Podcasts only.
class PodcastLibrary {
  PodcastLibrary._();

  static const showBox = 'PodcastShowLibrary';
  static const archiveBox = 'PodcastArchived';
  static const keepKey = 'podcastKeepLatest';
  static const autoDeleteKey = 'podcastAutoDelete';

  /// Bumped on every change, for Obx.
  static final rev = 0.obs;

  static Box? _box(String name) => Hive.isBoxOpen(name) ? Hive.box(name) : null;

  static Map _show(String? key) {
    if (key == null) return const {};
    final raw = _box(showBox)?.get(key);
    return raw is Map ? raw : const {};
  }

  static int _keepValue(dynamic v) =>
      v is int && keepLatestChoices.contains(v) ? v : 0;

  // Defaults (Podcast settings).
  static int get defaultKeepLatest => _keepValue(_box('AppPrefs')?.get(keepKey));
  static AutoDeletePolicy get defaultAutoDelete =>
      parseAutoDelete(_box('AppPrefs')?.get(autoDeleteKey));

  static Future<void> setDefaultKeepLatest(int n) async {
    await _box('AppPrefs')?.put(keepKey, _keepValue(n));
    _archiveRemoveWhere((show) => !_show(show).containsKey('keep'));
    rev.value++;
  }

  static Future<void> setDefaultAutoDelete(AutoDeletePolicy p) async {
    await _box('AppPrefs')?.put(autoDeleteKey, p.name);
    rev.value++;
    sweepDownloads();
  }

  // Per show (show page). Null = use the default.
  static int? keepOverride(String? show) {
    final v = _show(show)['keep'];
    return v is int ? _keepValue(v) : null;
  }

  static AutoDeletePolicy? autoDeleteOverride(String? show) {
    final v = _show(show)['autoDelete'];
    return v is String ? parseAutoDelete(v) : null;
  }

  static int keepLatestFor(String? show) =>
      keepOverride(show) ?? defaultKeepLatest;
  static AutoDeletePolicy autoDeleteFor(String? show) =>
      autoDeleteOverride(show) ?? defaultAutoDelete;

  static Future<void> _putShow(String show, String field, Object? value) async {
    final b = _box(showBox);
    if (b == null) return;
    final next = Map<String, dynamic>.from(_show(show));
    if (value == null) {
      next.remove(field);
    } else {
      next[field] = value;
    }
    next.isEmpty ? await b.delete(show) : await b.put(show, next);
  }

  static Future<void> setShowKeepLatest(String show, int? n) async {
    await _putShow(show, 'keep', n == null ? null : _keepValue(n));
    // A new limit starts fresh: what the old one hid comes back, and the
    // next Inbox refresh applies the new one.
    _archiveRemoveWhere((s) => s == show);
    rev.value++;
  }

  static Future<void> setShowAutoDelete(String show, AutoDeletePolicy? p) async {
    await _putShow(show, 'autoDelete', p?.name);
    rev.value++;
    sweepDownloads();
  }

  // New episodes into the queue and downloads (per show only). Each job
  // keeps its choice, when it was switched on, and the episodes it has
  // looked at.
  static const _queueJob =
      (mode: 'queueNew', since: 'queueSince', seen: 'queueSeen');
  static const _downloadJob = (mode: 'dlNew', since: 'dlSince', seen: 'dlSeen');

  /// Most episode ids a show remembers as looked at, per job (the Inbox
  /// keeps a show's latest dozen or so).
  static const queueSeenLimit = 100;

  static NewEpisodesQueue newEpisodesQueueFor(String? show) =>
      parseNewEpisodesQueue(_show(show)[_queueJob.mode]);

  static NewEpisodesDownload newEpisodesDownloadFor(String? show) =>
      parseNewEpisodesDownload(_show(show)[_downloadJob.mode]);

  /// Switching it on counts episodes from now; switching between top and
  /// end keeps what's been looked at.
  static Future<void> setShowNewEpisodesQueue(
          String show, NewEpisodesQueue mode, {DateTime? now}) =>
      _setJob(show, _queueJob, mode == NewEpisodesQueue.off ? null : mode.name,
          now);

  /// As [setShowNewEpisodesQueue].
  static Future<void> setShowNewEpisodesDownload(
          String show, NewEpisodesDownload mode, {DateTime? now}) =>
      _setJob(show, _downloadJob,
          mode == NewEpisodesDownload.off ? null : mode.name, now);

  static Future<void> _setJob(
      String show,
      ({String mode, String since, String seen}) job,
      String? mode,
      DateTime? now) async {
    final b = _box(showBox);
    if (b == null) return;
    final next = Map<String, dynamic>.from(_show(show));
    if (mode == null) {
      next
        ..remove(job.mode)
        ..remove(job.since)
        ..remove(job.seen);
    } else {
      if (next[job.mode] == null) {
        next[job.since] = (now ?? DateTime.now()).millisecondsSinceEpoch;
        next.remove(job.seen);
      }
      next[job.mode] = mode;
    }
    next.isEmpty ? await b.delete(show) : await b.put(show, next);
    rev.value++;
  }

  /// [merged]'s episodes by show, for the shows [wants].
  static Map<String, List<MediaItem>> _byShow(
      List<MediaItem> merged, bool Function(String show) wants) {
    final byShow = <String, List<MediaItem>>{};
    for (final e in merged) {
      final key = podcastShowKey(e);
      if (key != null && wants(key)) (byShow[key] ??= []).add(e);
    }
    return byShow;
  }

  /// [show]'s episodes in [eps] new to [job] ([newEpisodesSince]), still to
  /// play (not played, not archived). The rest count as looked at from now
  /// on; with [hold] (waiting for Wi-Fi) the new ones stay new for later.
  static List<MediaItem> _takeNew(Box b, String show, List<MediaItem> eps,
      ({String mode, String since, String seen}) job,
      {bool hold = false}) {
    final cfg = Map<String, dynamic>.from(_show(show));
    final seenRaw = cfg[job.seen];
    final seen = seenRaw is List ? {for (final id in seenRaw) '$id'} : null;
    final since = cfg[job.since];
    final fresh = [
      for (final e in newEpisodesSince(eps,
          seen: seen, sinceMs: since is int ? since : 0))
        if (!PodcastProgressService.isPlayed(e.id) && !isArchived(e.id)) e
    ];
    final held = hold ? {for (final e in fresh) e.id} : const <String>{};
    cfg[job.seen] = {
      for (final e in eps)
        if (!held.contains(e.id)) e.id,
      ...?seen,
    }.take(queueSeenLimit).toList();
    b.put(show, cfg);
    return hold ? const [] : fresh;
  }

  /// Puts the new episodes of shows that ask for it in the podcast queue
  /// ([newEpisodesSince]; unplayed, not archived), at the top (after the
  /// episode playing, when that's the first) or the end. Run on each Inbox
  /// refresh with every followed show's recent episodes.
  static void queueNewEpisodes(List<MediaItem> merged) {
    final b = _box(showBox);
    if (b == null || !Get.isRegistered<PodcastQueueController>()) return;
    final top = <MediaItem>[];
    final end = <MediaItem>[];
    final shows = _byShow(
        merged, (show) => newEpisodesQueueFor(show) != NewEpisodesQueue.off);
    for (final MapEntry(key: show, value: eps) in shows.entries) {
      (newEpisodesQueueFor(show) == NewEpisodesQueue.top ? top : end)
          .addAll(_takeNew(b, show, eps, _queueJob));
    }
    if (top.isEmpty && end.isEmpty) return;
    final queue = Get.find<PodcastQueueController>();
    for (final e in end) {
      queue.add(e);
    }
    var at = _afterPlaying(queue);
    for (final e in top) {
      if (queue.isQueued(e.id)) continue;
      queue.insertAt(at++, e);
    }
  }

  /// The top of the queue: after its first episode when that one's playing.
  static int _afterPlaying(PodcastQueueController queue) {
    if (queue.queue.isEmpty || !Get.isRegistered<PlayerController>()) return 0;
    final playing = Get.find<PlayerController>().currentSong.value?.id;
    return queue.queue.first.id == playing ? 1 : 0;
  }

  /// The new episodes of shows that download them ([newEpisodesSince];
  /// unplayed, not archived, not downloaded yet, with audio to download).
  /// On a [metered] connection, "On Wi-Fi" shows' new episodes wait for the
  /// next refresh on Wi-Fi.
  static List<MediaItem> takeNewDownloads(List<MediaItem> merged,
      {required bool metered}) {
    final b = _box(showBox);
    if (b == null) return const [];
    final out = <MediaItem>[];
    final shows = _byShow(merged,
        (show) => newEpisodesDownloadFor(show) != NewEpisodesDownload.off);
    for (final MapEntry(key: show, value: eps) in shows.entries) {
      final wait =
          metered && newEpisodesDownloadFor(show) == NewEpisodesDownload.wifi;
      out.addAll([
        for (final e in _takeNew(b, show, eps, _downloadJob, hold: wait))
          if (!PodcastDownloadService.isDownloaded(e.id) &&
              ((e.extras?['url'] as String?)?.isNotEmpty ?? false))
            e
      ]);
    }
    return out;
  }

  /// Downloads [takeNewDownloads]' episodes one after another. Run on each
  /// Inbox refresh.
  static Future<void> downloadNewEpisodes(List<MediaItem> merged) async {
    final shows = _byShow(merged,
        (show) => newEpisodesDownloadFor(show) != NewEpisodesDownload.off);
    if (shows.isEmpty) return;
    final metered = await NetworkKind.isMetered();
    for (final e in takeNewDownloads(merged, metered: metered)) {
      await PodcastDownloadService.download(e);
    }
  }

  // Archive.
  static bool isArchived(String id) => _box(archiveBox)?.containsKey(id) ?? false;

  static String? _archivedShow(dynamic v) =>
      v is Map && v['show'] is String ? v['show'] as String : null;

  static void _archiveRemoveWhere(bool Function(String? show) test) {
    final b = _box(archiveBox);
    if (b == null) return;
    final drop = [
      for (final k in b.keys)
        if (test(_archivedShow(b.get(k)))) k
    ];
    if (drop.isNotEmpty) b.deleteAll(drop);
  }

  /// Apply each show's "Keep latest" to a merged inbox: archive the older
  /// unplayed episodes (and take them out of Up Next), and return the list
  /// without anything archived.
  static List<MediaItem> applyKeepLatest(List<MediaItem> merged,
      {DateTime? now}) {
    final byShow = <String, List<MediaItem>>{};
    for (final e in merged) {
      final key = podcastShowKey(e);
      if (key != null) (byShow[key] ??= []).add(e);
    }
    final archive = _box(archiveBox);
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final inProgress = {
      for (final r in _safeInProgress()) '${r['id']}',
    };
    for (final entry in byShow.entries) {
      final keep = keepLatestFor(entry.key);
      if (keep <= 0) continue;
      final ids = sortNewestFirst(entry.value).map((e) => e.id).toList();
      final drop = episodesToArchive(ids, keep,
          isPlayed: PodcastProgressService.isPlayed,
          inProgress: inProgress.contains);
      for (final id in drop) {
        if (archive != null && !archive.containsKey(id)) {
          archive.put(id, {'at': at, 'show': entry.key});
        }
        if (Get.isRegistered<PodcastQueueController>()) {
          Get.find<PodcastQueueController>().removeById(id);
        }
      }
    }
    return [for (final e in merged) if (!isArchived(e.id)) e];
  }

  static List<Map<String, dynamic>> _safeInProgress() {
    try {
      return PodcastProgressService.inProgress();
    } catch (_) {
      return const [];
    }
  }

  /// Newest first by `pubDateMs` (undated last, order kept).
  static List<MediaItem> sortNewestFirst(List<MediaItem> eps) {
    final indexed = [for (var i = 0; i < eps.length; i++) (i, eps[i])];
    int ms(MediaItem e) => (e.extras?['pubDateMs'] as int?) ?? 0;
    indexed.sort((a, b) {
      final am = ms(a.$2), bm = ms(b.$2);
      if (am == bm) return a.$1.compareTo(b.$1);
      if (am == 0) return 1;
      if (bm == 0) return -1;
      return bm.compareTo(am);
    });
    return [for (final p in indexed) p.$2];
  }

  // Auto-delete.
  static int? _playedAt(String id) {
    final v = _box('PodcastPlayed')?.get(id);
    return v is int ? v : null;
  }

  /// Delete finished downloads whose show says so. [currentId] (the episode
  /// playing) and starred episodes (AntennaPod keeps favourites') are left
  /// alone. Returns how many were deleted.
  static Future<int> sweepDownloads({String? currentId, DateTime? now}) async {
    if (!Hive.isBoxOpen('PodcastDownloads')) return 0;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    var n = 0;
    try {
      for (final item in PodcastDownloadService.downloadedItems()) {
        if (StarredEpisodes.isStarred(item.id)) continue;
        final policy = autoDeleteFor(podcastShowKey(item));
        if (downloadDueForDeletion(policy, _playedAt(item.id), nowMs,
            isCurrent: item.id == currentId)) {
          await PodcastDownloadService.delete(item.id);
          n++;
        }
      }
    } catch (e) {
      printERROR('Download sweep failed: $e');
    }
    return n;
  }

  // Mark all as listened.
  /// Without [sweep], downloads that are due to go after listening stay
  /// until the next sweep, so Undo finds them (a swipe can be a slip).
  static ListenedSnapshot markAllListened(List<MediaItem> episodes,
      {bool sweep = true}) {
    final snapshot = listenedSnapshot(episodes);
    for (final id in snapshot.ids) {
      PodcastProgressService.markPlayed(id);
    }
    rev.value++;
    if (sweep) sweepDownloads();
    return snapshot;
  }

  /// What marking [episodes] played changes, for [undoMarkAll]: those not
  /// played yet, where you were in them and their places in the queue.
  static ListenedSnapshot listenedSnapshot(List<MediaItem> episodes) {
    final ids = planMarkAllListened(
        episodes.map((e) => e.id), PodcastProgressService.isPlayed);
    final progressBox = _box('PodcastProgress');
    final progress = <String, dynamic>{
      for (final id in ids)
        if (progressBox?.get(id) != null) id: progressBox!.get(id)
    };
    final queued = <(int, MediaItem)>[];
    if (Get.isRegistered<PodcastQueueController>()) {
      final q = Get.find<PodcastQueueController>().queue;
      for (var i = 0; i < q.length; i++) {
        if (ids.contains(q[i].id)) queued.add((i, q[i]));
      }
    }
    return ListenedSnapshot(ids, progress, queued);
  }

  static Future<void> undoMarkAll(ListenedSnapshot s) async {
    for (final id in s.ids) {
      PodcastProgressService.markUnplayed(id);
    }
    final progressBox = _box('PodcastProgress');
    for (final e in s.progress.entries) {
      await progressBox?.put(e.key, e.value);
    }
    if (Get.isRegistered<PodcastQueueController>()) {
      final c = Get.find<PodcastQueueController>();
      for (final (i, item) in s.queued) {
        c.insertAt(i, item);
      }
    }
    rev.value++;
  }

  /// Facts the filter chips look at, from the stores.
  static EpisodeFacts factsFor(MediaItem e, {Set<String>? bookmarked}) {
    final queued = Get.isRegistered<PodcastQueueController>() &&
        Get.find<PodcastQueueController>().isQueued(e.id);
    return EpisodeFacts(
      played: PodcastProgressService.isPlayed(e.id),
      inProgress: PodcastProgressService.positionMs(e.id) != null,
      queued: queued,
      downloaded: PodcastDownloadService.isDownloaded(e.id),
      bookmarked: (bookmarked ??
              {for (final b in PodcastBookmarkStore.all) b.episodeId})
          .contains(e.id),
      duration: e.duration,
    );
  }
}
