import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'spotify_api_service.dart';
import 'spotify_auth_service.dart';
import 'spotify_connect_models.dart';
import 'spotify_import_service.dart';

/// Spotify Connect: Riff as a remote for the user's Spotify devices
/// (Premium). The music plays in Spotify; Riff's own player isn't touched.
class SpotifyConnect {
  SpotifyConnect._();

  static const deviceKey = 'spotifyConnectDevice';

  /// How often the remote panel refreshes while it's open.
  static const pollEvery = Duration(seconds: 3);

  static final devices = <SpotifyDevice>[].obs;
  static final state = Rxn<SpotifyPlaybackState>();
  static final lastError = Rxn<SpotifyApiException>();
  static Timer? _poll;
  static var _watchers = 0;
  static var _polling = false;

  /// Whether the app is on screen. Polling pauses while it isn't: audio
  /// keeps the process alive in the background, and an open remote panel
  /// otherwise kept calling the Web API every few seconds for hours.
  @visibleForTesting
  static bool Function() isForeground = () {
    final s = SchedulerBinding.instance.lifecycleState;
    return s == null ||
        s == AppLifecycleState.resumed ||
        s == AppLifecycleState.inactive;
  };

  static SpotifyApiService api = SpotifyApiService(auth: SpotifyAuthService());

  static bool get enabled => SpotifyAuthService.connectOn;

  /// Whether the current sign-in may see and control playback.
  static bool get hasAccess =>
      SpotifyAuthService.isConnected &&
      SpotifyAuthService.playbackScopes
          .every((s) => !SpotifyAuthService.lacksScope(s));

  static Future<void> setEnabled(bool on) async {
    await Hive.box('AppPrefs').put(SpotifyAuthService.connectKey, on);
    if (!on) {
      _poll?.cancel();
      _poll = null;
      devices.clear();
      state.value = null;
    }
  }

  static String? get preferredDeviceId {
    final v = Hive.box('AppPrefs').get(deviceKey);
    return v is String && v.isNotEmpty ? v : null;
  }

  /// Forget the account's devices (sign-out).
  static Future<void> forgetAccount() async {
    await Hive.box('AppPrefs').delete(deviceKey);
    devices.clear();
    state.value = null;
    lastError.value = null;
  }

  static Future<void> rememberDevice(String id) =>
      Hive.box('AppPrefs').put(deviceKey, id);

  /// Load devices and what's playing. Errors go to [lastError].
  static Future<void> refresh() async {
    try {
      final d = await api.fetchDevices();
      final s = await api.fetchPlaybackState();
      devices.assignAll(d);
      state.value = s;
      lastError.value = null;
    } on SpotifyApiException catch (e) {
      lastError.value = e;
    } catch (_) {
      lastError.value = const SpotifyApiException(SpotifyErrorKind.server);
    }
  }

  /// Refresh every [pollEvery] while at least one screen watches.
  static void watch() {
    _watchers++;
    if (_watchers == 1) {
      unawaited(_tick());
      _poll = Timer.periodic(pollEvery, (_) => unawaited(_tick()));
    }
  }

  /// One poll: skipped while the app is in the background, and while the
  /// previous one is still running (a slow answer or a rate-limit wait
  /// used to stack up another pair of requests every [pollEvery]).
  static Future<void> _tick() async {
    if (_polling || !isForeground()) return;
    _polling = true;
    try {
      await refresh();
    } finally {
      _polling = false;
    }
  }

  static void unwatch() {
    _watchers = (_watchers - 1).clamp(0, 1 << 20);
    if (_watchers == 0) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Play [body] (`connectPlayBody`) on [deviceId]. When Spotify says no
  /// device is active, wake it with a transfer and try once more.
  static Future<void> playOn(String deviceId, Map<String, dynamic> body,
      {SpotifyApiService? client}) async {
    final c = client ?? api;
    try {
      await c.play(deviceId: deviceId, body: body);
    } on SpotifyApiException catch (e) {
      if (e.kind != SpotifyErrorKind.noActiveDevice) rethrow;
      await c.transferPlayback(deviceId, play: false);
      await c.play(deviceId: deviceId, body: body);
    }
    await rememberDevice(deviceId);
  }

  /// Play these tracks (or this playlist/album, [contextUri]) on a device.
  static Future<void> playTracks(String deviceId,
      {List<SpotifyTrackRef> tracks = const [],
      String? contextUri,
      int start = 0,
      SpotifyApiService? client}) {
    final (ids, at) = spotifyIdsFrom(tracks, start);
    return playOn(
        deviceId,
        connectPlayBody(
            contextUri: contextUri,
            trackIds: ids,
            start: contextUri != null ? start : at),
        client: client);
  }

  /// A control, then a quick refresh so the panel shows the result.
  static Future<void> command(
      Future<void> Function(String? deviceId) run) async {
    try {
      await run(state.value?.device?.id);
      lastError.value = null;
    } on SpotifyApiException catch (e) {
      lastError.value = e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await refresh();
  }
}
