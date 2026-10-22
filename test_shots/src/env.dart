import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/audiobook_catalog_service.dart';
import 'package:harmonymusic/services/discovery/discovery_repository.dart';
import 'package:harmonymusic/services/free_audiobook_service.dart';
import 'package:hive/hive.dart';

/// Every Hive box the screens read, opened in memory
/// (`Hive.openBox(name, bytes: …)`): nothing touches the disk, and code
/// that calls `Hive.openBox(name)` itself gets the already-open box.
const shotBoxNames = [
  // initHiveCritical / initHiveDeferred (lib/main.dart)
  'SongsCache', 'SongDownloads', 'SongsUrlCache', 'AppPrefs',
  'homeScreenData', 'BannedSongs', 'BannedArtists', 'BannedCollections',
  'NotInterested', 'SongStats', 'PodcastSubs', 'LIBFAV', 'PendingDownloads',
  'PodcastFeedMemo', 'DailyStats', 'SquareCovers', 'PodcastQueue',
  'PodcastFolders', 'SavedAudiobooks', 'SavedFreeAudiobooks',
  'PodcastDownloads', 'PodcastProgress', 'AudiobookProgress',
  'AudiobookDownloads', 'PodcastPlayed', 'PodcastShowPrefs',
  'PodcastSegmentCache', 'PodcastManualSegments', 'PodcastStats',
  'PodcastTranscripts', 'PodcastBookmarks', 'PodcastHistory',
  'PodcastStarred', 'AudiobookBookmarks', 'PodcastShowLibrary',
  'PodcastArchived', 'PodcastInboxCache', 'TrackAnalysisCache',
  'PlaylistMixPrefs', 'SyncLedger',
  // opened on demand by the screens
  'LIBRP', 'LibraryPlaylists', 'LibraryAlbums', 'LibraryArtists',
  'LibraryPodcasts', 'blacklistedPlaylist', 'prevSessionData',
  'lyrics', 'searchQuery', 'SpotifyCache',
  // DiscoveryRepository (Stats reads its events)
  ...DiscoveryBoxes.all,
];

/// Extra boxes (a playlist's or an album's songs) opened by seeding.
final _extraBoxes = <String>{};

Future<Box> openShotBox(String name) async {
  if (Hive.isBoxOpen(name)) return Hive.box(name);
  _extraBoxes.add(name);
  return Hive.openBox(name, bytes: Uint8List(0));
}

Future<void> openShotBoxes() async {
  for (final name in shotBoxNames) {
    await openShotBox(name);
  }
}

/// Empties every box, so each scenario starts from the same seed.
Future<void> clearShotBoxes() async {
  for (final name in {...shotBoxNames, ..._extraBoxes}) {
    if (Hive.isBoxOpen(name)) await Hive.box(name).clear();
  }
}

/// Scratch folder standing in for the app's support / documents / cache
/// directories.
late Directory shotTmp;

/// Answers the plugins the screens call on start (paths, secure storage,
/// the app's own channels) so nothing throws MissingPluginException.
void mockShotPlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => shotTmp.path);
  for (final name in const [
    'plugins.it_nomads.com/flutter_secure_storage',
    'dev.fluttercommunity.plus/package_info',
    'dev.fluttercommunity.plus/wakelock_plus',
    'flutter.baseflow.com/permissions/methods',
    'riff/apps',
    'riff/device_music',
    'riff/downloads',
    'riff/episode_alerts',
    'riff/mic',
    'riff/network',
    'riff/newpipe',
    'riff/video',
    'riff/widget',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(name), (call) async => null);
  }
}

/// Canned HTTP for the services whose Dio is exposed for tests (the free
/// and store audiobook catalogues): [routes] maps a URL fragment to a
/// JSON body; anything else answers 404.
class ShotHttpAdapter implements HttpClientAdapter {
  ShotHttpAdapter(this.routes);
  final Map<String, Object> Function(Uri uri)? Function(Uri uri) routes;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final responder = routes(options.uri);
    if (responder == null) {
      return ResponseBody.fromString('{}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    return ResponseBody.fromString(jsonEncode(responder(options.uri)), 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void installShotHttp(
    Map<String, Object> Function(Uri uri)? Function(Uri uri) routes) {
  final adapter = ShotHttpAdapter(routes);
  // ignore: invalid_use_of_visible_for_testing_member
  FreeAudiobookService.dio.httpClientAdapter = adapter;
  // ignore: invalid_use_of_visible_for_testing_member
  AudiobookCatalogService.dio.httpClientAdapter = adapter;
}
