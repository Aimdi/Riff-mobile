/// The sleep timer turning itself on at night, as AntennaPod's automatic
/// sleep timer does: when playback starts within the hours you set (by
/// default 22:00 to 06:00) and no sleep timer runs, it starts for the
/// length you picked last. Turn a sleep timer off within those hours and
/// none starts by itself again until they're over. Off by default.
library;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

class AutoSleepTimer {
  AutoSleepTimer._();

  /// AppPrefs keys.
  static const key = 'autoSleepTimer';
  static const fromKey = 'autoSleepTimerFrom';
  static const toKey = 'autoSleepTimerTo';

  /// The last length a timed sleep timer was started with, in minutes.
  static const minutesKey = 'sleepTimerLastMinutes';

  /// The hours it starts and stops at (AntennaPod's), and the length
  /// it uses before you've picked one.
  static const defaultFrom = 22;
  static const defaultTo = 6;
  static const defaultMinutes = 30;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  static int _hourOf(Object? raw, int fallback) =>
      raw is int && raw >= 0 && raw < Duration.hoursPerDay ? raw : fallback;

  static final enabled = RxBool(_prefs?.get(key) == true);
  static final from = RxInt(_hourOf(_prefs?.get(fromKey), defaultFrom));
  static final to = RxInt(_hourOf(_prefs?.get(toKey), defaultTo));

  /// Until when you've turned it off (a sleep timer turned off within its
  /// hours).
  static DateTime? _declinedUntil;

  /// Reads the settings again (tests, after AppPrefs opens).
  @visibleForTesting
  static void reload() {
    enabled.value = _prefs?.get(key) == true;
    from.value = _hourOf(_prefs?.get(fromKey), defaultFrom);
    to.value = _hourOf(_prefs?.get(toKey), defaultTo);
    _declinedUntil = null;
  }

  static Future<void> setEnabled(bool on) async {
    enabled.value = on;
    _declinedUntil = null;
    await _prefs?.put(key, on);
  }

  /// Its hours: from [fromHour] to [toHour] (0–23).
  static Future<void> setHours({int? fromHour, int? toHour}) async {
    if (fromHour != null) from.value = _hourOf(fromHour, from.value);
    if (toHour != null) to.value = _hourOf(toHour, to.value);
    _declinedUntil = null;
    await _prefs?.putAll({fromKey: from.value, toKey: to.value});
  }

  /// The length it starts the sleep timer with: the one picked last.
  static int get minutes {
    final raw = _prefs?.get(minutesKey);
    return raw is int && raw > 0 ? raw : defaultMinutes;
  }

  /// A timed sleep timer was started for [length] minutes: the next one
  /// it starts is as long.
  static Future<void> rememberMinutes(int length) async {
    if (length > 0) await _prefs?.put(minutesKey, length);
  }

  /// Whether [now] is within its hours, [fromHour] to [toHour]: hours that
  /// end before they start run past midnight, and the same hour twice is
  /// all day (as in AntennaPod).
  static bool inHours(DateTime now, int fromHour, int toHour) {
    final hour = now.hour;
    if (fromHour == toHour) return true;
    if (fromHour < toHour) return fromHour <= hour && hour < toHour;
    return hour >= fromHour || hour < toHour;
  }

  /// When the hours that [now] is in are over (all-day hours: at the next
  /// [fromHour]).
  static DateTime hoursEnd(DateTime now, int fromHour, int toHour) {
    final end = fromHour == toHour ? fromHour : toHour;
    final today = DateTime(now.year, now.month, now.day, end);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, end);
  }

  /// Whether playback starting at [now] starts the sleep timer, none
  /// running ([timerRunning]).
  static bool startsAt(DateTime now, {required bool timerRunning}) {
    if (!enabled.value || timerRunning) return false;
    final declined = _declinedUntil;
    if (declined != null && now.isBefore(declined)) return false;
    return inHours(now, from.value, to.value);
  }

  /// You turned a sleep timer off at [now]: within its hours, it doesn't
  /// start one again until they're over.
  static void decline(DateTime now) {
    if (!enabled.value || !inHours(now, from.value, to.value)) return;
    _declinedUntil = hoursEnd(now, from.value, to.value);
  }
}
