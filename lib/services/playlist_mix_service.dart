import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Transition style between two tracks in Mix mode (Spotify-like).
enum MixTransitionStyle {
  auto,
  fade,
  rise,
  blend,
  off;

  String get labelKey {
    switch (this) {
      case MixTransitionStyle.auto:
        return 'mixTransitionAuto';
      case MixTransitionStyle.fade:
        return 'mixTransitionFade';
      case MixTransitionStyle.rise:
        return 'mixTransitionRise';
      case MixTransitionStyle.blend:
        return 'mixTransitionBlend';
      case MixTransitionStyle.off:
        return 'mixTransitionOff';
    }
  }

  /// Crossfade window before the track ends.
  Duration get fadeDuration {
    switch (this) {
      case MixTransitionStyle.auto:
        return const Duration(milliseconds: 4500);
      case MixTransitionStyle.fade:
        return const Duration(milliseconds: 3500);
      case MixTransitionStyle.rise:
        return const Duration(milliseconds: 2500);
      case MixTransitionStyle.blend:
        return const Duration(milliseconds: 7000);
      case MixTransitionStyle.off:
        return Duration.zero;
    }
  }

  static MixTransitionStyle fromName(String? name) {
    return MixTransitionStyle.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MixTransitionStyle.auto,
    );
  }
}

/// Persists Mix on/off + per-gap transition styles, and drives live playback fades.
class PlaylistMixService extends GetxService {
  static const boxName = 'PlaylistMixPrefs';

  /// True while the current queue should use Mix crossfades.
  final mixPlaybackActive = false.obs;

  MixTransitionStyle playbackStyle = MixTransitionStyle.auto;
  String? activePlaylistId;
  int activeIndex = 0;

  Box get _box {
    if (!Hive.isBoxOpen(boxName)) {
      throw StateError('$boxName box not open');
    }
    return Hive.box(boxName);
  }

  bool isMixEnabled(String playlistId) {
    if (!Hive.isBoxOpen(boxName) || playlistId.isEmpty) return false;
    final raw = _box.get(playlistId);
    if (raw is Map) return raw['enabled'] == true;
    return false;
  }

  Future<void> setMixEnabled(String playlistId, bool enabled) async {
    if (!Hive.isBoxOpen(boxName) || playlistId.isEmpty) return;
    final raw = _box.get(playlistId);
    final cur = Map<String, dynamic>.from(raw is Map ? raw : const {});
    cur['enabled'] = enabled;
    cur['transitions'] ??= <String, String>{};
    await _box.put(playlistId, cur);
  }

  MixTransitionStyle transitionAt(String playlistId, int gapIndex) {
    if (!Hive.isBoxOpen(boxName) || playlistId.isEmpty) {
      return MixTransitionStyle.auto;
    }
    final raw = _box.get(playlistId);
    if (raw is! Map) return MixTransitionStyle.auto;
    final transitions = raw['transitions'];
    if (transitions is! Map) return MixTransitionStyle.auto;
    return MixTransitionStyle.fromName('${transitions['$gapIndex']}');
  }

  Future<void> setTransitionAt(
    String playlistId,
    int gapIndex,
    MixTransitionStyle style,
  ) async {
    if (!Hive.isBoxOpen(boxName) || playlistId.isEmpty) return;
    final raw = _box.get(playlistId);
    final cur = Map<String, dynamic>.from(raw is Map ? raw : const {});
    final transitions = Map<String, String>.from(
      (cur['transitions'] is Map)
          ? (cur['transitions'] as Map).map((k, v) => MapEntry('$k', '$v'))
          : const <String, String>{},
    );
    transitions['$gapIndex'] = style.name;
    cur['transitions'] = transitions;
    cur['enabled'] = cur['enabled'] == true;
    await _box.put(playlistId, cur);
  }

  /// Call when starting playlist playback so the audio handler can fade.
  void activatePlayback({
    required bool enabled,
    required String playlistId,
    int startIndex = 0,
    MixTransitionStyle? style,
  }) {
    mixPlaybackActive.value = enabled;
    activePlaylistId = playlistId;
    activeIndex = startIndex;
    playbackStyle = style ??
        (enabled
            ? transitionAt(playlistId, startIndex)
            : MixTransitionStyle.off);
  }

  /// Refresh style for the gap after [index] (song that just finished).
  void advancePlaybackIndex(int nextIndex) {
    activeIndex = nextIndex;
    if (mixPlaybackActive.isTrue &&
        activePlaylistId != null &&
        activePlaylistId!.isNotEmpty) {
      playbackStyle = transitionAt(activePlaylistId!, nextIndex);
    }
  }

  void deactivatePlayback() {
    mixPlaybackActive.value = false;
    activePlaylistId = null;
  }
}
