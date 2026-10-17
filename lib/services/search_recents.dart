/// What you opened from search, as Spotify's and Apple Music's recent
/// searches list it: the songs you played and the artists, albums,
/// playlists and podcasts you opened from search results, newest first,
/// shown on the search page before you type, to open again with one tap.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/media_Item_builder.dart';
import '/models/playlist.dart';

enum SearchRecentKind { song, artist, album, playlist }

/// One of [SearchRecents.items]: a [MediaItem], an [Artist], an [Album] or
/// a [Playlist] (a podcast too), as [kind] says.
class SearchRecent {
  const SearchRecent(this.kind, this.item);

  final SearchRecentKind kind;
  final Object item;

  String get id => switch (item) {
        final MediaItem song => song.id,
        final Artist artist => artist.browseId,
        final Album album => album.browseId,
        final Playlist playlist => playlist.playlistId,
        _ => '',
      };

  /// From what a search result is; null for anything else.
  static SearchRecent? of(Object item) => switch (item) {
        MediaItem() => SearchRecent(SearchRecentKind.song, item),
        Artist() => SearchRecent(SearchRecentKind.artist, item),
        Album() => SearchRecent(SearchRecentKind.album, item),
        Playlist() => SearchRecent(SearchRecentKind.playlist, item),
        _ => null,
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'item': switch (item) {
          final MediaItem song => MediaItemBuilder.toJson(song),
          final Artist artist => artist.toJson(),
          final Album album => album.toJson(),
          final Playlist playlist => playlist.toJson(),
          _ => const <String, dynamic>{},
        },
      };

  static SearchRecent? fromJson(Object? raw) {
    if (raw is! Map || raw['item'] is! Map) return null;
    final json = Map<String, dynamic>.from(raw['item'] as Map);
    try {
      final kind = SearchRecentKind.values.byName('${raw['kind']}');
      final recent = SearchRecent(
          kind,
          switch (kind) {
            SearchRecentKind.song => MediaItemBuilder.fromJson(json),
            SearchRecentKind.artist => Artist.fromJson(json),
            SearchRecentKind.album => Album.fromJson(json),
            SearchRecentKind.playlist => Playlist.fromJson(json),
          });
      return recent.id.isEmpty ? null : recent;
    } catch (_) {
      return null;
    }
  }
}

class SearchRecents {
  SearchRecents._();

  /// AppPrefs: what was opened, newest first.
  static const key = 'searchRecentItems';

  /// How many are kept.
  static const max = 10;

  /// Bumps when the list changes.
  static final rev = 0.obs;

  static Box? get _prefs =>
      Hive.isBoxOpen('AppPrefs') ? Hive.box('AppPrefs') : null;

  /// AppPrefs: whether nothing searched for or opened from search is kept
  /// (YouTube Music's and Metrolist's Pause search history).
  static const pausedKey = 'searchHistoryPaused';

  static final paused = RxBool(_prefs?.get(pausedKey) == true);

  static Future<void> setPaused(bool on) async {
    paused.value = on;
    await _prefs?.put(pausedKey, on);
  }

  /// Reads the switch again (tests, after AppPrefs opens).
  @visibleForTesting
  static void reload() => paused.value = _prefs?.get(pausedKey) == true;

  static List<Object?> get _raw {
    final raw = _prefs?.get(key);
    return raw is List ? raw : const [];
  }

  static List<SearchRecent> get items =>
      _raw.map(SearchRecent.fromJson).whereType<SearchRecent>().toList();

  /// [item] opened (or played): first in the list, once.
  static Future<void> note(Object item) async {
    if (paused.value) return;
    final recent = SearchRecent.of(item);
    final prefs = _prefs;
    if (recent == null || recent.id.isEmpty || prefs == null) return;
    final kept = [
      recent,
      ...items.where((r) => r.kind != recent.kind || r.id != recent.id),
    ].take(max);
    await prefs.put(key, [for (final r in kept) r.toJson()]);
    rev.value++;
  }

  static Future<void> remove(SearchRecent recent) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.put(key, [
      for (final r in items)
        if (r.kind != recent.kind || r.id != recent.id) r.toJson(),
    ]);
    rev.value++;
  }

  static Future<void> clear() async {
    await _prefs?.delete(key);
    rev.value++;
  }
}

/// Marks the search results: what's opened from inside them is kept in
/// [SearchRecents] ([noteSearchOpen]); a page opened from there isn't.
class SearchRecentsScope extends InheritedWidget {
  const SearchRecentsScope({super.key, required super.child});

  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SearchRecentsScope>() != null;

  @override
  bool updateShouldNotify(SearchRecentsScope oldWidget) => false;
}

/// Keeps [item] in [SearchRecents] when [context] is in the search results.
void noteSearchOpen(BuildContext context, Object item) {
  if (SearchRecentsScope.within(context)) unawaited(SearchRecents.note(item));
}
