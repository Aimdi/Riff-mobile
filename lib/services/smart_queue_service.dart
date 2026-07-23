import 'dart:async';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/services/discovery/discovery_service.dart';
import '/ui/player/player_controller.dart';
import '/utils/helper.dart';

/// Echo Brain–lite: when the queue runs low, inject similar tracks on-device.
class SmartQueueService extends GetxService {
  Worker? _queueWorker;
  Worker? _songWorker;
  bool _injecting = false;
  DateTime _lastInject = DateTime.fromMillisecondsSinceEpoch(0);

  SmartQueueService init() {
    return this;
  }

  void attach(PlayerController player) {
    _queueWorker?.dispose();
    _songWorker?.dispose();
    _queueWorker = ever(player.currentQueue, (_) => _maybeInject(player));
    _songWorker = ever(player.currentSong, (_) => _maybeInject(player));
  }

  bool get enabled => Hive.box('AppPrefs').get('smartQueueInjection') ?? true;

  Future<void> _maybeInject(PlayerController player) async {
    if (!enabled || _injecting) return;
    if (!Get.isRegistered<DiscoveryService>()) return;
    final song = player.currentSong.value;
    if (song == null) return;
    // Skip podcasts / offline files.
    if (song.id.startsWith('podcast_') ||
        '${song.extras?['url'] ?? ''}'.contains('file')) {
      return;
    }
    final q = player.currentQueue;
    final idx = player.currentSongIndex.value;
    if (idx < 0) return;
    final remaining = q.length - idx - 1;
    if (remaining > 2) return;
    if (DateTime.now().difference(_lastInject) < const Duration(seconds: 20)) {
      return;
    }

    _injecting = true;
    try {
      final disc = Get.find<DiscoveryService>();
      final batch = await disc.moreLikeThisPlayNext(song, limit: 5);
      if (batch.isEmpty) return;
      final existing = q.map((e) => e.id).toSet();
      final fresh = batch
          .where((m) => !existing.contains(m.id))
          .take(3)
          .toList();
      if (fresh.isEmpty) return;
      await player.enqueueSongList(fresh);
      _lastInject = DateTime.now();
      printINFO('SmartQueue: injected ${fresh.length} similar tracks');
    } catch (e) {
      printINFO('SmartQueue inject failed: $e');
    } finally {
      _injecting = false;
    }
  }

  @override
  void onClose() {
    _queueWorker?.dispose();
    _songWorker?.dispose();
    super.onClose();
  }
}
