/// Spotify Connect (remote control of a Spotify device through the Web
/// API): devices, what's playing, and the request bodies. Pure Dart.
library;

import 'dart:convert';

import 'spotify_import_service.dart';

/// A device Spotify can play on (phone app, desktop app, speaker…).
class SpotifyDevice {
  const SpotifyDevice({
    required this.id,
    required this.name,
    this.type = '',
    this.isActive = false,
    this.isRestricted = false,
    this.volumePercent,
  });

  final String id;
  final String name;

  /// `Smartphone`, `Computer`, `Speaker`, `TV`, …
  final String type;
  final bool isActive;

  /// Spotify won't take commands for it.
  final bool isRestricted;

  /// Null when the device's volume can't be set.
  final int? volumePercent;
}

/// What a device is playing.
class SpotifyPlaybackState {
  const SpotifyPlaybackState({
    required this.isPlaying,
    this.progressMs = 0,
    this.track,
    this.device,
    this.shuffle = false,
  });

  final bool isPlaying;
  final int progressMs;
  final SpotifyTrackRef? track;
  final SpotifyDevice? device;
  final bool shuffle;
}

Map<String, dynamic>? _decode(String body) {
  try {
    final j = jsonDecode(body);
    return j is Map ? Map<String, dynamic>.from(j) : null;
  } catch (_) {
    return null;
  }
}

SpotifyDevice? parseDevice(Object? d) {
  if (d is! Map) return null;
  final id = d['id'];
  final name = d['name'];
  if (id is! String || id.isEmpty || name is! String) return null;
  final vol = d['volume_percent'];
  return SpotifyDevice(
    id: id,
    name: name,
    type: '${d['type'] ?? ''}',
    isActive: d['is_active'] == true,
    isRestricted: d['is_restricted'] == true,
    volumePercent: d['supports_volume'] == false
        ? null
        : (vol is num ? vol.toInt() : null),
  );
}

/// `GET /me/player/devices`.
List<SpotifyDevice> parseDevices(String body) {
  final list = _decode(body)?['devices'];
  return [
    if (list is List)
      for (final d in list)
        if (parseDevice(d) case final dev?) dev
  ];
}

/// `GET /me/player`; null when nothing is playing anywhere (204, empty).
SpotifyPlaybackState? parsePlaybackState(String body,
    {required SpotifyTrackRef? Function(Object? item) parseTrack}) {
  if (body.trim().isEmpty) return null;
  final j = _decode(body);
  if (j == null) return null;
  final progress = j['progress_ms'];
  return SpotifyPlaybackState(
    isPlaying: j['is_playing'] == true,
    progressMs: progress is num ? progress.toInt() : 0,
    track: parseTrack(j['item']),
    device: parseDevice(j['device']),
    shuffle: j['shuffle_state'] == true,
  );
}

/// The device to play on: the one picked before if it's there, else the
/// active one, else the first that takes commands.
SpotifyDevice? pickTargetDevice(List<SpotifyDevice> devices,
    {String? preferredId}) {
  final usable = devices.where((d) => !d.isRestricted).toList();
  if (usable.isEmpty) return null;
  for (final d in usable) {
    if (d.id == preferredId) return d;
  }
  for (final d in usable) {
    if (d.isActive) return d;
  }
  return usable.first;
}

/// Most track URIs sent in one play request.
const connectMaxUris = 100;

/// Body of `PUT /me/player/play`.
///
/// A playlist or album plays as itself ([contextUri], e.g.
/// `spotify:playlist:…`) from [start]; other lists (Liked Songs, top,
/// search, radio) as track URIs. Long lists are cut to a window of
/// [connectMaxUris] that keeps the tapped track.
Map<String, dynamic> connectPlayBody({
  String? contextUri,
  List<String> trackIds = const [],
  int start = 0,
}) {
  if (contextUri != null) {
    return {
      'context_uri': contextUri,
      if (start > 0) 'offset': {'position': start},
    };
  }
  if (trackIds.isEmpty) return const {};
  final s = start.clamp(0, trackIds.length - 1);
  var from = 0;
  if (trackIds.length > connectMaxUris) {
    from = (s - connectMaxUris ~/ 4).clamp(0, trackIds.length - connectMaxUris);
  }
  final window =
      trackIds.sublist(from, (from + connectMaxUris).clamp(0, trackIds.length));
  return {
    'uris': [for (final id in window) 'spotify:track:$id'],
    if (s - from > 0) 'offset': {'position': s - from},
  };
}

/// The Spotify ids of [tracks] (rows without one, like CSV imports, are
/// left out) and where [start] lands among them.
(List<String>, int) spotifyIdsFrom(List<SpotifyTrackRef> tracks, int start) {
  final ids = <String>[];
  var at = 0;
  for (var i = 0; i < tracks.length; i++) {
    final id = tracks[i].id;
    if (id.isEmpty || id.startsWith('csv_')) continue;
    if (i < start) at++;
    ids.add(id);
  }
  return (ids, ids.isEmpty ? 0 : at.clamp(0, ids.length - 1));
}
