import 'dart:async';

import 'package:get/get.dart';
import 'package:harmonymusic/services/music_service.dart';

/// [MusicServices] without the network: each call is answered by the test
/// through a [Completer] (or fails with [error] when set). Unused members
/// fall through to [noSuchMethod].
class FakeMusicServices extends GetxService implements MusicServices {
  /// When set, every request below throws it.
  Object? error;

  /// Pending `search` calls by filter (null for the overview search).
  final searches = <String?, List<Completer<Map<String, dynamic>>>>{};
  final suggestionCalls = <String>[];
  int playlistCalls = 0;
  int artistCalls = 0;

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) {
    if (error != null) return Future.error(error!);
    final c = Completer<Map<String, dynamic>>();
    (searches[filter] ??= []).add(c);
    return c.future;
  }

  @override
  Future<List<String>> getSearchSuggestion(String queryStr) async {
    suggestionCalls.add(queryStr);
    if (error != null) throw error!;
    return ['$queryStr suggestion'];
  }

  @override
  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int? limit,
      bool related = false,
      int suggestionsLimit = 0}) async {
    playlistCalls++;
    if (error != null) throw error!;
    return {'tracks': const []};
  }

  @override
  Future<Map<String, dynamic>> getArtist(String channelId) async {
    artistCalls++;
    if (error != null) throw error!;
    return const {};
  }

  int homeCalls = 0;

  @override
  Future<dynamic> getHome({int limit = 4, String? params}) async {
    homeCalls++;
    if (error != null) throw error!;
    return [];
  }

  /// Pending artist tab loads by category ("Songs", "Albums", ...).
  final artistTabs = <String, List<Completer<Map<String, dynamic>>>>{};

  @override
  Future<Map<String, dynamic>> getArtistRealtedContent(
      Map<String, dynamic> browseEndpoint, String category,
      {String additionalParams = ""}) {
    if (error != null) return Future.error(error!);
    final c = Completer<Map<String, dynamic>>();
    (artistTabs[category] ??= []).add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
