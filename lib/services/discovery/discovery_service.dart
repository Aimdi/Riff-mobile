import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../models/thumbnail.dart';
import '../ban_service.dart';
import '../music_service.dart';
import 'candidate_sources.dart';
import 'discovery_engine.dart';
import 'discovery_repository.dart';
import 'discovery_types.dart';
import 'mix_generator.dart';
import 'taste_model.dart';

/// GetX service wiring the discovery stack into the app.
class DiscoveryService extends GetxService {
  late final DiscoveryRepository repo;
  late final TasteModel taste;
  late final CandidateSources sources;
  late final DiscoveryEngine engine;

  final isReady = false.obs;
  final isGenerating = false.obs;
  final personalSections = <DiscoverySection>[].obs;
  final dailyMixes = <GeneratedMix>[].obs;
  final mixesUpdatedPill = false.obs;

  /// Track previous media for play-ended fraction.
  MediaItem? _prevMedia;
  int _prevPositionMs = 0;
  int _songStartedAtMs = 0;
  DiscoverySource _prevSource = DiscoverySource.unknown;

  Future<DiscoveryService> init() async {
    repo = DiscoveryRepository();
    await repo.open();
    await repo.pruneEvents();

    BanServiceSafe.setBanHook(BanService.isBanned);

    taste = TasteModel(repo);
    final music = Get.find<MusicServices>();
    sources = CandidateSources(music: music, repo: repo);
    final exploration =
        (repo.getPref('exploration', defaultValue: 0.5) as num).toDouble();
    engine = DiscoveryEngine(
      repo: repo,
      taste: taste,
      sources: sources,
      exploration: exploration,
    );

    // Backfill once from SongStats
    if (repo.getPref('backfilledFromStats') != true) {
      try {
        if (Hive.isBoxOpen('SongStats')) {
          await repo.backfillFromSongStats(Hive.box('SongStats'));
        }
      } catch (_) {}
    }

    isReady.value = true;

    // Lazy load cached mixes for Home (no network)
    dailyMixes.assignAll(repo.mixesOfKind(MixKind.dailyMix));

    // Fire-and-forget regeneration well after Home/cache paint + first play.
    Future.delayed(const Duration(seconds: 12), () {
      maybeRegenerateMixes();
    });

    return this;
  }

  // ─── Settings ─────────────────────────────────────────────────────────

  double get exploration =>
      (repo.getPref('exploration', defaultValue: 0.5) as num).toDouble();

  set exploration(double v) {
    repo.setPref('exploration', v.clamp(0.0, 1.0));
    engine.exploration = v.clamp(0.0, 1.0);
  }

  bool get wifiOnlyGeneration =>
      repo.getPref('wifiOnlyGeneration', defaultValue: true) as bool? ?? true;

  set wifiOnlyGeneration(bool v) => repo.setPref('wifiOnlyGeneration', v);

  int get mixCount => repo.getPref('mixCount', defaultValue: 4) as int? ?? 4;

  set mixCount(int v) => repo.setPref('mixCount', v.clamp(3, 5));

  bool get unheardOnlyDefault =>
      repo.getPref('unheardOnlyDefault', defaultValue: false) as bool? ?? false;

  set unheardOnlyDefault(bool v) => repo.setPref('unheardOnlyDefault', v);

  bool get listenBrainzRecs =>
      repo.getPref('listenBrainzRecs', defaultValue: false) as bool? ?? false;

  set listenBrainzRecs(bool v) => repo.setPref('listenBrainzRecs', v);

  Future<void> resetTasteModel() async {
    await repo.resetTasteModel();
    personalSections.clear();
    dailyMixes.clear();
  }

  Map<String, dynamic> debugSnapshot() => repo.affinityDebugSnapshot();

  // ─── Playback signal hooks ────────────────────────────────────────────

  /// Call when the current media item changes (play started).
  Future<void> onMediaChanged(MediaItem? next, {int positionMs = 0}) async {
    // Close out previous
    if (_prevMedia != null) {
      final totalMs = _prevMedia!.duration?.inMilliseconds ?? 0;
      // Prefer continuous position; fall back to wall-clock if position reset
      var listened = positionMs > 0 ? positionMs : _prevPositionMs;
      if (listened <= 0 && _songStartedAtMs > 0) {
        listened = DateTime.now().millisecondsSinceEpoch - _songStartedAtMs;
      }
      await taste.logPlayEnded(
        videoId: _prevMedia!.id,
        artist: _prevMedia!.artist,
        title: _prevMedia!.title,
        source: _prevSource,
        listenedMs: listened,
        // Never fabricate a denominator: an unresolved/unknown duration must
        // stay 0 so TasteModel scores it as unknown instead of a 100% listen.
        totalMs: totalMs,
      );
    }

    _prevMedia = next;
    _prevPositionMs = 0;
    _songStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (next != null) {
      _prevSource =
          DiscoverySource.fromWire(next.extras?['discoverySource'] as String?);
      await taste.logPlayStarted(
        videoId: next.id,
        artist: next.artist,
        title: next.title,
        source: _prevSource,
      );
    }
  }

  void onPositionTick(int positionMs) {
    _prevPositionMs = positionMs;
  }

  Future<void> onFavorite(MediaItem song, {required bool add}) =>
      taste.logFavorite(song.id, song.artist, song.title, add: add);

  Future<void> onPlaylistAdd(MediaItem song) =>
      taste.logPlaylistAdd(song.id, song.artist, song.title);

  Future<void> onDownload(MediaItem song) =>
      taste.logDownload(song.id, song.artist, song.title);

  Future<void> onFollow(String artistName, {required bool follow}) =>
      taste.logFollow(artistName, follow: follow);

  Future<void> onNeverPlay(MediaItem song) =>
      taste.logNeverPlay(song.id, song.artist, song.title);

  Future<void> onThumbs(MediaItem song, {required bool up, String? surface}) =>
      taste.logThumbs(
        videoId: song.id,
        artist: song.artist,
        title: song.title,
        up: up,
        surface: surface,
      );

  Future<void> onDismiss(MediaItem song, {String? surface}) => taste.logDismiss(
        videoId: song.id,
        artist: song.artist,
        title: song.title,
        surface: surface,
      );

  // ─── Mix scheduler (resume / launch, no WorkManager) ──────────────────

  DateTime? _lastMixRegenAt;

  Future<void> maybeRegenerateMixes({bool force = false}) async {
    if (!isReady.value || isGenerating.value) return;
    // Avoid resume/launch double-firing within a short window.
    if (!force &&
        _lastMixRegenAt != null &&
        DateTime.now().difference(_lastMixRegenAt!) <
            const Duration(minutes: 15)) {
      return;
    }
    if (!force && wifiOnlyGeneration) {
      // Best-effort: if we cannot know connectivity, allow generation.
      // Callers on mobile can pass force or set wifiOnly false.
    }
    isGenerating.value = true;
    try {
      // Rediscover first (local, free)
      await engine.rediscover();
      final mixes = await engine.dailyMixes();
      dailyMixes.assignAll(mixes);
      await engine.freshFinds();
      await engine.releaseRadar();
      await materializeMixPlaylists();

      if (taste.hasEnoughSignal) {
        final sections = await engine.homeSections();
        personalSections.assignAll(sections);
      }
      _lastMixRegenAt = DateTime.now();
      mixesUpdatedPill.value = true;
      Future.delayed(const Duration(seconds: 4), () {
        mixesUpdatedPill.value = false;
      });
    } catch (_) {
      // Never crash surfaces
    } finally {
      isGenerating.value = false;
    }
  }

  /// Write system playlists into LibraryPlaylists + per-id song boxes
  /// so Library / offline / Android Auto can open them.
  Future<void> materializeMixPlaylists() async {
    try {
      final lib = await Hive.openBox('LibraryPlaylists');
      for (final mix in repo.allMixes()) {
        final playlistId = 'RIFF_${mix.id}';
        await lib.put(playlistId, {
          'title': mix.title,
          'playlistId': playlistId,
          'description': mix.reason,
          'thumbnails': [
            {
              'url': mix.tracks.isNotEmpty
                  ? Thumbnail.bestUrl(mix.tracks.first['thumbnails'],
                      target: 'extraHigh')
                  : ''
            }
          ],
          'itemCount': '${mix.tracks.length}',
          'isPipedPlaylist': false,
          'isCloudPlaylist': false,
          'kind': mix.kind,
        });
        final songs = await Hive.openBox(playlistId);
        await songs.clear();
        for (final t in mix.tracks) {
          final id = t['videoId'] as String? ?? '';
          if (id.isEmpty) continue;
          await songs.put(id, t);
        }
        await songs.close();
      }
    } catch (_) {}
  }

  Future<void> refreshPersonalHome() async {
    if (!taste.hasEnoughSignal) {
      personalSections.clear();
      return;
    }
    try {
      personalSections.assignAll(await engine.homeSections());
    } catch (_) {}
  }

  // ─── Convenience ──────────────────────────────────────────────────────

  Future<List<MediaItem>> similarSongs(MediaItem seed,
          {int limit = 25, bool unheardOnly = false}) =>
      engine.similarSongs(seed, limit: limit, unheardOnly: unheardOnly);

  Future<List<MediaItem>> smartRadioBatch(
    MediaItem seed, {
    required List<MediaItem> sessionHistory,
    int limit = 24,
  }) =>
      engine.smartRadioBatch(
        seed,
        exploration: exploration,
        sessionHistory: sessionHistory,
        limit: limit,
      );

  Future<List<MediaItem>> moreLikeThisPlayNext(MediaItem seed,
      {int limit = 5}) async {
    final list = await similarSongs(seed, limit: limit, unheardOnly: false);
    return list;
  }

  /// Tag a MediaItem with discovery source.
  static MediaItem withSource(MediaItem item, DiscoverySource source) {
    final extras = Map<String, dynamic>.from(item.extras ?? {});
    extras['discoverySource'] = source.wireName;
    return item.copyWith(extras: extras);
  }

  static List<MediaItem> tagAll(List<MediaItem> items, DiscoverySource source) {
    return items.map((e) => withSource(e, source)).toList();
  }
}
