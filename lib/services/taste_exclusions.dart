/// Playlists left out of your taste profile, as Spotify's "Exclude from
/// your Taste Profile" (a sleep, white-noise or kids' playlist): what
/// plays from one isn't counted in your stats and Rewind, doesn't steer
/// recommendations and isn't sent to ListenBrainz. It still shows in
/// Recently played, as Spotify keeps it in your history.
library;

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/playling_from.dart';

class TasteExclusions {
  TasteExclusions._();

  /// AppPrefs: the playlists left out (their ids, without YouTube's VL).
  static const key = 'tasteExcludedPlaylists';

  /// Bumps when one is left out or let back in.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// YouTube's playlist pages and its playlists' own ids differ by VL.
  static String _id(String playlistId) =>
      playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId.trim();

  static Set<String> get playlists {
    final raw = _prefs?.get(key);
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  static bool excludes(String playlistId) =>
      playlistId.isNotEmpty && playlists.contains(_id(playlistId));

  /// Whether what's playing [from] is left out: from a playlist that is.
  static bool excludesPlay(PlaylingFrom from) =>
      from.type == PlaylingFromType.PLAYLIST && excludes(from.id);

  static Future<void> setExcluded(String playlistId, bool excluded) async {
    if (playlistId.isEmpty) return;
    final ids = playlists;
    final changed =
        excluded ? ids.add(_id(playlistId)) : ids.remove(_id(playlistId));
    if (!changed) return;
    await _prefs?.put(key, ids.toList());
    rev.value++;
  }
}
