import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'music_service.dart';
import 'spotify_like_sync.dart' show LikeOp, queueLikeOp;
import 'yt_auth_service.dart';

/// Keeps your likes in step with YouTube Music once your YouTube account
/// is connected (opt-in), as Metrolist syncs them: a song liked in Riff is
/// liked in YouTube Music too, so it's in Liked music there and steers the
/// feed Riff shows you; unliked in Riff, it's unliked there if Riff liked
/// it there. Changes go a few seconds after they're made, in order, and
/// wait (across restarts) while YouTube can't be reached.
class YtLikeSync {
  YtLikeSync._();

  static const queueBox = 'YtLikeQueue';
  static const addedBox = 'YtLikedByRiff';

  /// AppPrefs: whether likes are kept in step.
  static const enabledKey = 'ytLikeSync';

  /// Wait this long after a change before sending, to batch changes.
  static const debounce = Duration(seconds: 10);

  /// Changes not sent yet.
  static final pending = 0.obs;

  /// Bumps when the switch changes.
  static final rev = 0.obs;

  static Timer? _timer;
  static Future<void>? _flushing;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static bool get enabled => _prefs?.get(enabledKey) == true;

  /// Rates [videoId] on the connected account ('like/like' or
  /// 'like/removelike'); whether YouTube took it. Tests replace it.
  @visibleForTesting
  static Future<bool> Function(String endpoint, String videoId) send =
      (endpoint, videoId) =>
          Get.find<MusicServices>().rateSong(endpoint, videoId);

  /// Whether a YouTube account is connected; tests replace it.
  @visibleForTesting
  static bool Function() connected = () => YtAuthService.isConnected;

  static Future<Box> _open(String name) async =>
      Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);

  static Future<void> setEnabled(bool on) async {
    await _prefs?.put(enabledKey, on);
    rev.value++;
    if (!on) {
      _timer?.cancel();
      await (await _open(queueBox)).clear();
      pending.value = 0;
    }
  }

  /// Forget what belongs to the disconnected account: the changes not sent
  /// and which songs Riff liked there.
  static Future<void> forgetAccount() async {
    _timer?.cancel();
    for (final name in [queueBox, addedBox]) {
      await (await _open(name)).clear();
    }
    pending.value = 0;
  }

  /// A song was added to or taken out of Riff's Favorites.
  static Future<void> onFavorite(MediaItem song, {required bool add}) async {
    if (!enabled || !connected() || !_videoId.hasMatch(song.id)) return;
    try {
      final box = await _open(queueBox);
      final current = <String, LikeOp>{
        for (final k in box.keys)
          if (_opOf(box.get(k)) case final op?) '$k': op
      };
      final next =
          queueLikeOp(current, song.id, add ? LikeOp.save : LikeOp.remove);
      if (next.containsKey(song.id)) {
        await box.put(song.id, {'op': next[song.id]!.name});
      } else {
        await box.delete(song.id);
      }
      pending.value = box.length;
      flushSoon();
    } catch (e) {
      printERROR('YouTube like queue failed: $e');
    }
  }

  static LikeOp? _opOf(Object? v) => v is Map
      ? LikeOp.values.firstWhereOrNull((o) => o.name == v['op'])
      : null;

  static void flushSoon({Duration delay = debounce}) {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(flush()));
  }

  /// Send what's waiting, oldest first; one flush at a time. Stops at the
  /// first change YouTube doesn't take (offline, signed out) and keeps it
  /// and the rest for the next time.
  static Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  static Future<void> _flush() async {
    if (!enabled || !connected()) return;
    final queue = await _open(queueBox);
    final added = await _open(addedBox);
    try {
      for (final key in queue.keys.toList()) {
        final videoId = '$key';
        final op = _opOf(queue.get(key));
        if (op == LikeOp.save) {
          if (!await send('like/like', videoId)) break;
          await added.put(videoId, DateTime.now().millisecondsSinceEpoch);
        } else if (op == LikeOp.remove && added.containsKey(videoId)) {
          // Only a like Riff made goes: one made in YouTube Music stays.
          if (!await send('like/removelike', videoId)) break;
          await added.delete(videoId);
        }
        await queue.delete(key);
      }
    } catch (e) {
      printERROR('YouTube like sync failed: $e');
    } finally {
      pending.value = queue.length;
    }
  }
}
