/// New-episode notifications (Podcast settings), as Pocket Casts,
/// AntennaPod and Apple Podcasts send them: every few hours, with Riff
/// closed too, Android reads the start of each followed show's feed
/// (EpisodeAlerts.kt) and posts a notification for a show with episodes
/// it hadn't seen there before. Tapped, it opens the Podcasts Inbox
/// ([inboxLink]). Off until switched on; Android only.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';

import '/services/podcast_service.dart';
import '/utils/helper.dart';

class NewEpisodeAlerts {
  NewEpisodeAlerts._();

  static const channel = MethodChannel('riff/episode_alerts');

  /// AppPrefs: switched on.
  static const prefKey = 'podcastNewEpisodeAlerts';

  /// What a notification opens (EpisodeAlerts.kt's INBOX_LINK).
  static final inboxLink =
      Uri(scheme: 'riff', host: 'podcasts', path: '/inbox');

  /// Whether [uri] is a notification's [inboxLink].
  static bool opensInbox(Uri uri) =>
      uri.scheme == inboxLink.scheme && uri.host == inboxLink.host;

  static final enabled = false.obs;

  /// AppPrefs: the followed shows (feed addresses) whose new episodes
  /// don't notify, as Pocket Casts, Apple Podcasts and AntennaPod let a
  /// show be left out.
  static const mutedKey = 'podcastAlertsMuted';

  /// Bumps when a show is left out or let back in.
  static final mutedRev = 0.obs;

  static Set<String> get muted {
    final raw = _prefs?.get(mutedKey);
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  /// Whether the show at [feed] notifies (while they're on at all).
  static bool notifiesFor(String feed) => !muted.contains(feed);

  /// Lets the show at [feed] notify again, or leaves it out.
  static Future<void> setNotifiesFor(String feed, bool on) async {
    final shows = muted;
    if (!(on ? shows.remove(feed) : shows.add(feed))) return;
    await _prefs?.put(mutedKey, shows.toList());
    mutedRev.value++;
    await sync();
  }

  static bool get available => defaultTargetPlatform == TargetPlatform.android;

  static Worker? _follows;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// At start-up: the switch as it was, and Android told which shows to
  /// look at, then again whenever a show is followed or unfollowed.
  static Future<void> start() async {
    if (!available) return;
    enabled.value = _prefs?.get(prefKey) == true;
    _follows ??= ever<int>(PodcastService.subsRev, (_) => sync());
    await sync();
  }

  /// Switched on (after asking for permission to notify; false when it
  /// was refused, and it stays off) or off.
  static Future<bool> setEnabled(bool on) async {
    if (on && !await _mayNotify()) return false;
    enabled.value = on;
    await _prefs?.put(prefKey, on);
    await _send();
    return true;
  }

  /// Tells Android the shows followed now, and the notification's words
  /// in the app's language (so again after the language changes).
  static Future<void> sync() async {
    if (enabled.value) await _send();
  }

  static Future<void> _send() async {
    if (!available) return;
    try {
      await channel.invokeMethod<bool>('set', {
        'on': enabled.value,
        'shows': alertShows(PodcastService.subscriptions, muted: muted),
        'channel': 'newEpisodes'.tr,
        'count': 'newEpisodesCount'.tr,
      });
    } catch (e) {
      printERROR('New episode alerts: $e');
    }
  }

  /// Android 13's permission to notify, asked for; false when refused.
  static Future<bool> _mayNotify() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted || status.isLimited;
    } catch (e) {
      // Can't ask: Android won't show them without it, so nothing lost.
      printERROR('Notifications permission: $e');
      return true;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _follows?.dispose();
    _follows = null;
    enabled.value = false;
    mutedRev.value = 0;
  }
}

/// The followed shows Android looks at, as {feed, title, art}: those with
/// a web feed, but the [muted].
List<Map<String, String>> alertShows(
        Iterable<Map<String, dynamic>> subscriptions,
        {Set<String> muted = const {}}) =>
    [
      for (final s in subscriptions)
        if (_isWebAddress('${s['feedUrl'] ?? ''}') &&
            !muted.contains(s['feedUrl']))
          {
            'feed': '${s['feedUrl']}',
            'title': '${s['title'] ?? ''}',
            'art': '${s['artwork'] ?? ''}',
          },
    ];

bool _isWebAddress(String address) =>
    address.startsWith('https://') || address.startsWith('http://');
